import Foundation
import Combine
import CryptoKit

@MainActor
final class LibraryStore: ObservableObject {
    @Published var session: Session?
    @Published var tracks: [Track] = []
    @Published var busy = false
    @Published var progress = ""
    @Published var error: String?
    @Published var pathFailures = 0
    @Published var lastPathError = ""
    @Published var indexed = 0
    private var work: Task<Void, Never>?
    private var revision = UUID()
    var api: MusicAPI? { session.map { MusicAPI($0) } }
    var missingPaths: Int { tracks.filter { $0.path.isEmpty }.count }

    init() {
        session = Keychain.read()
        if let session, let data = try? Data(contentsOf: cacheURL(session)),
           let saved = try? JSONDecoder().decode([Track].self, from: data) { tracks = saved }
    }
    private func cacheURL(_ session: Session) -> URL {
        let key = SHA256.hash(data: Data((session.base.absoluteString + "|" + session.username).utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("library-\(key).json")
    }
    private func saveCache() {
        guard let session, let data = try? JSONEncoder().encode(tracks) else { return }
        do { try data.write(to: cacheURL(session), options: [.atomic, .completeFileProtectionUnlessOpen]) }
        catch { self.error = "曲库可用，但本机缓存保存失败：\(error.localizedDescription)" }
    }
    func login(address: String, username: String, password: String) async throws {
        let session = try await MusicAPI.login(address: address, username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        try Keychain.save(session)
        self.session = session
        tracks = []
        refresh()
    }
    func logout() {
        cancel()
        if let session { try? FileManager.default.removeItem(at: cacheURL(session)) }
        Keychain.clear()
        session = nil
        tracks = []
        error = nil
    }
    func cancel() {
        revision = UUID()
        work?.cancel()
        work = nil
        busy = false
        progress = "已暂停，可重新同步"
    }
    func refresh(rebuildPaths: Bool = false) {
        cancel()
        guard let api else { return }
        let currentRevision = revision
        busy = true
        error = nil
        pathFailures = 0
        lastPathError = ""
        indexed = 0
        progress = "正在读取飞牛曲库…"
        let savedPaths = Dictionary(tracks.map { ($0.id, $0.path) }, uniquingKeysWith: { first, _ in first })
        work = Task {
            do {
                var received: [Track] = []
                var ids = Set<String>()
                var page = 1
                while true {
                    try Task.checkCancellation()
                    let (batch, total) = try await api.tracks(page: page)
                    guard revision == currentRevision else { return }
                    var added = 0
                    for var track in batch where ids.insert(track.id).inserted {
                        if !rebuildPaths && track.path.isEmpty { track.path = savedPaths[track.id] ?? "" }
                        received.append(track)
                        added += 1
                    }
                    progress = "正在读取歌曲 \(received.count) / \(total)"
                    if received.count >= total { break }
                    if added == 0 { throw MusicError(message: "歌曲分页提前结束，保留上次曲库。请重试同步。") }
                    page += 1
                }
                tracks = received.sorted { $0.createdAt > $1.createdAt }
                saveCache()
                let missing = tracks.filter { $0.path.isEmpty }
                let positions = Dictionary(uniqueKeysWithValues: tracks.enumerated().map { ($0.element.id, $0.offset) })
                for start in stride(from: 0, to: missing.count, by: 4) {
                    try Task.checkCancellation()
                    let batch = Array(missing[start..<min(start + 4, missing.count)])
                    let results = await withTaskGroup(of: (String, String, String?).self) { group in
                        for song in batch {
                            group.addTask {
                                do { return (song.id, try await api.filePath(id: song.id), nil) }
                                catch { return (song.id, "", error.localizedDescription) }
                            }
                        }
                        var results: [(String, String, String?)] = []
                        for await result in group { results.append(result) }
                        return results
                    }
                    guard revision == currentRevision else { return }
                    for (id, path, failure) in results {
                        if let position = positions[id] { tracks[position].path = path }
                        if let failure { pathFailures += 1; lastPathError = failure }
                        indexed += 1
                    }
                    progress = "建立目录索引 \(indexed) / \(missing.count)"
                    if indexed % 40 == 0 { saveCache() }
                }
                guard revision == currentRevision else { return }
                saveCache()
                progress = "已同步 \(tracks.count) 首 · \(tracks.count - missingPaths) 首具有文件路径"
                busy = false
            } catch {
                guard revision == currentRevision else { return }
                if !(error is CancellationError) { self.error = error.localizedDescription }
                busy = false
            }
        }
    }
}
