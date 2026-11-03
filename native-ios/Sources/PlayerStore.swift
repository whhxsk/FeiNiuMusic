import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class PlayerStore: ObservableObject {
    @Published var current: Track?
    @Published var playing = false
    @Published var loading = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var error: String?
    @Published var useTranscode = false
    private let player = AVPlayer()
    private var queue: [Track] = []
    private var index = 0
    private var api: MusicAPI?
    private var generation = UUID()
    private var request: Task<Void, Never>?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var playingObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var transcodingID: String?

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.position = time.seconds.isFinite ? max(0, time.seconds) : 0
                let length = self.player.currentItem?.duration.seconds ?? 0
                self.duration = length.isFinite ? max(0, length) : 0
                self.updateNowPlaying()
            }
        }
        playingObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.playing = self.player.timeControlStatus == .playing
                self.loading = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, let item = note.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.next()
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            if let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, raw == AVAudioSession.InterruptionType.began.rawValue {
                Task { @MainActor in self?.pause() }
            }
        }
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            if let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt, raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.pause() }
            }
        }
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(event.positionTime) }
            return .success
        }
    }
    func play(_ track: Track, in tracks: [Track], api: MusicAPI) {
        queue = tracks
        index = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
        self.api = api
        start(track)
    }
    private func releaseTranscode() {
        if let id = transcodingID, let api {
            Task { _ = try? await api.request("/track/transcode/quit", body: ["guid": id]) }
        }
        transcodingID = nil
    }
    private func start(_ track: Track) {
        guard let api else { return }
        request?.cancel()
        releaseTranscode()
        generation = UUID()
        let ticket = generation
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = track
        error = nil
        loading = true
        position = 0
        duration = 0
        updateNowPlaying()
        request = Task {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                var url = api.url("/track/stream", query: ["guid": track.id])
                if useTranscode {
                    let response = try await api.request("/track/transcode", body: ["guid": track.id, "output": ["codec": "mp3", "channel": 2]])
                    guard generation == ticket else { return }
                    transcodingID = track.id
                    guard let path = response["url"] as? String, let result = URL(string: path, relativeTo: api.session.base)?.absoluteURL else {
                        throw MusicError(message: "飞牛没有返回转码地址，请尝试原音播放")
                    }
                    url = result
                }
                try Task.checkCancellation()
                guard generation == ticket else { return }
                let cookies = api.cookie.map { [$0] } ?? []
                let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: cookies])
                let item = AVPlayerItem(asset: asset)
                statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    let failure = item.error?.localizedDescription
                    let status = item.status
                    Task { @MainActor in
                        guard let self, self.generation == ticket else { return }
                        if status == .failed {
                            self.error = "播放失败：\(failure ?? "音频格式或服务器响应不兼容")。可在设置开启 MP3 转码后重试。"
                            self.loading = false
                        }
                    }
                }
                player.replaceCurrentItem(with: item)
                player.play()
            } catch {
                guard generation == ticket else { return }
                self.error = error.localizedDescription
                loading = false
            }
        }
    }
    func pause() { player.pause(); playing = false; updateNowPlaying() }
    func resume() { guard current != nil else { return }; player.play() }
    func toggle() { playing ? pause() : resume() }
    func seek(_ seconds: Double) { player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600)) }
    func next() {
        guard index + 1 < queue.count else { pause(); return }
        index += 1
        start(queue[index])
    }
    func previous() {
        if position > 3 { seek(0); return }
        guard index > 0 else { seek(0); return }
        index -= 1
        start(queue[index])
    }
    func stop() {
        generation = UUID()
        request?.cancel()
        releaseTranscode()
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = nil
        queue = []
        playing = false
        loading = false
        error = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private func updateNowPlaying() {
        guard let track = current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist, MPMediaItemPropertyAlbumTitle: track.album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0]
    }
}
