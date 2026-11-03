import SwiftUI

@main
struct FeiniuLiteApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerStore()
    var body: some Scene {
        WindowGroup {
            Group {
                if library.session == nil { LoginView() }
                else { MainView() }
            }
            .environmentObject(library).environmentObject(player)
            .tint(.teal)
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var library: LibraryStore
    @State private var address = UserDefaults.standard.string(forKey: "lastServer") ?? ""
    @State private var username = UserDefaults.standard.string(forKey: "lastUser") ?? ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Image(systemName: "waveform.circle.fill").font(.system(size: 70)).foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("牛听").font(.largeTitle.bold())
                        Text("你的音乐，按自己的方式收藏。").font(.title3).foregroundStyle(.secondary)
                        Text("连接飞牛音乐 · 原生 iOS 客户端").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 16) {
                        TextField("NAS 地址，如 http://192.168.1.10:5666", text: $address).keyboardType(.URL)
                            .textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Divider()
                        TextField("飞牛用户名", text: $username).textContentType(.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Divider()
                        SecureField("密码", text: $password).textContentType(.password)
                    }.padding(20).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.callout) }
                    Button {
                        busy = true
                        error = nil
                        Task {
                            do {
                                try await library.login(address: address, username: username, password: password)
                                UserDefaults.standard.set(address, forKey: "lastServer")
                                UserDefaults.standard.set(username, forKey: "lastUser")
                                password = ""
                            } catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    } label: {
                        HStack { Spacer(); if busy { ProgressView() }; Text(busy ? "正在连接…" : "连接我的音乐库").bold(); Spacer() }.padding(.vertical, 9)
                    }.buttonStyle(.borderedProminent).disabled(busy || address.isEmpty || username.isEmpty || password.isEmpty)
                    Text("使用可直连的局域网地址或 HTTPS 域名。当前版本不支持仅填写 FN ID；HTTPS 证书须有效。文件夹来自已入库歌曲的真实路径，无需增强插件。").font(.footnote).foregroundStyle(.secondary)
                }.padding(28).padding(.top, 28)
            }.background(Color(uiColor: .systemGroupedBackground))
        }
    }
}

struct MainView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: PlayerStore
    @State private var showPlayer = false
    var body: some View {
        TabView {
            NavigationStack { SongsView(recent: true) }.tabItem { Label("最近添加", systemImage: "clock.badge.plus") }
            NavigationStack { FolderView(parts: []) }.tabItem { Label("文件夹", systemImage: "folder") }
            NavigationStack { SongsView(recent: false) }.tabItem { Label("全部音乐", systemImage: "music.note.list") }
            NavigationStack { SettingsView() }.tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }
        .safeAreaInset(edge: .bottom) {
            if let song = player.current {
                HStack(spacing: 14) {
                    Button { showPlayer = true } label: {
                        HStack {
                            Image(systemName: "waveform").font(.title2).frame(width: 38, height: 38).background(.teal.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading) {
                                Text(song.title).font(.subheadline.bold()).lineLimit(1)
                                Text(player.error == nil ? song.artist : "播放遇到问题，点此查看").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }.buttonStyle(.plain)
                    if player.loading { ProgressView() }
                    Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 32, height: 40) }.accessibilityLabel(player.playing ? "暂停" : "播放")
                    Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 32, height: 40) }.accessibilityLabel("下一首")
                }.padding(.horizontal, 16).padding(.vertical, 8).background(.regularMaterial)
            }
        }
        .sheet(isPresented: $showPlayer) { PlayerView() }
        .task { if library.tracks.isEmpty && !library.busy { library.refresh() } }
    }
}

struct SyncStatus: View {
    @EnvironmentObject var library: LibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if library.busy {
                HStack {
                    ProgressView()
                    Text(library.progress).font(.caption)
                    Spacer()
                    Button("暂停") { library.cancel() }.font(.caption)
                }
            } else if !library.progress.isEmpty {
                Text(library.progress).font(.caption).foregroundStyle(.secondary)
            }
            if let error = library.error {
                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red)
                Button("重新同步") { library.refresh() }
            }
        }
    }
}

struct SongRows: View {
    let songs: [Track]
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: PlayerStore
    var body: some View {
        ForEach(songs) { song in
            Button {
                if let api = library.api { player.play(song, in: songs, api: api) }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: player.current?.id == song.id ? "waveform" : "music.note")
                        .foregroundStyle(.teal).frame(width: 42, height: 42)
                        .background(.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(song.title).foregroundStyle(.primary).lineLimit(1)
                        Text([song.artist, song.album].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: "play.circle").foregroundStyle(.tertiary)
                }.padding(.vertical, 3)
            }.buttonStyle(.plain)
            .contextMenu {
                if !song.path.isEmpty { ShareLink(item: song.path) { Label("分享文件路径", systemImage: "doc.on.doc") } }
            }
        }
    }
}

struct SongsView: View {
    let recent: Bool
    @EnvironmentObject var library: LibraryStore
    @State private var search = ""
    var songs: [Track] {
        let filtered = library.tracks.filter { search.isEmpty || ($0.title + $0.artist + $0.album).localizedCaseInsensitiveContains(search) }
        return recent ? filtered.sorted { $0.createdAt > $1.createdAt } : filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var body: some View {
        List {
            Section { SyncStatus() }
            if songs.isEmpty {
                Section { EmptyState(title: library.busy ? "正在读取音乐" : "没有找到歌曲", detail: "确认飞牛音乐中已扫描入库，或尝试重新同步。", icon: "music.note") }
            } else {
                Section("\(songs.count) 首 · \(recent ? "按入库时间倒序" : "按歌曲名排序")") { SongRows(songs: songs) }
            }
        }
        .navigationTitle(recent ? "最近添加" : "全部音乐")
        .searchable(text: $search, prompt: "搜索歌曲、歌手或专辑")
        .toolbar { Button { library.refresh() } label: { Image(systemName: "arrow.clockwise") }.disabled(library.busy).accessibilityLabel("同步曲库") }
        .refreshable { library.refresh() }
    }
}

struct FolderView: View {
    let parts: [String]
    @EnvironmentObject var library: LibraryStore
    @State private var search = ""
    private var folders: [FolderEntry] { FolderIndex.folders(library.tracks, at: parts) }
    private var songs: [Track] {
        if search.isEmpty { return FolderIndex.songs(library.tracks, at: parts) }
        return library.tracks.filter {
            !$0.path.isEmpty && Array($0.components.prefix(parts.count)) == parts &&
            ($0.title + $0.artist + $0.path).localizedCaseInsensitiveContains(search)
        }
    }
    var body: some View {
        List {
            Section {
                SyncStatus()
                Text(parts.isEmpty ? "根据已入库歌曲的文件路径显示目录" : "/" + parts.joined(separator: "/"))
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if parts.isEmpty && library.missingPaths > 0 {
                Section {
                    Label("\(library.missingPaths) 首尚无文件路径", systemImage: "info.circle").font(.subheadline)
                    Text(library.busy ? "正在通过飞牛音乐接口补查路径，可先浏览已建立的目录。" : "部分歌曲未返回路径或当前账号无权限。它们仍可在全部音乐中播放。可在设置中重新建立索引。")
                        .font(.caption).foregroundStyle(.secondary)
                    if !library.lastPathError.isEmpty { Text(library.lastPathError).font(.caption).foregroundStyle(.red) }
                }
            }
            if search.isEmpty && !folders.isEmpty {
                Section("文件夹") {
                    ForEach(folders) { folder in
                        NavigationLink { FolderView(parts: folder.parts) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "folder.fill").font(.title2).foregroundStyle(.teal)
                                Text(folder.name).lineLimit(2)
                                Spacer()
                                Text("\(folder.count)").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 7)
                        }
                    }
                }
            }
            if !songs.isEmpty { Section(search.isEmpty ? "此目录的歌曲" : "目录内搜索结果") { SongRows(songs: songs) } }
            if songs.isEmpty && (folders.isEmpty || !search.isEmpty) {
                EmptyState(title: library.busy ? "正在建立目录" : "暂无可显示的歌曲目录", detail: "这里只显示已入库且具有路径的歌曲，不显示空文件夹。", icon: "folder")
            }
        }
        .navigationTitle(parts.last ?? "文件夹")
        .searchable(text: $search, prompt: "搜索此目录及子目录")
        .refreshable { library.refresh() }
        .toolbar { Button { library.refresh() } label: { Image(systemName: "arrow.clockwise") }.disabled(library.busy).accessibilityLabel("同步文件夹") }
    }
}

struct EmptyState: View {
    let title: String
    let detail: String
    let icon: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 42)).foregroundStyle(.teal)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 35)
    }
}

struct SettingsView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: PlayerStore
    @State private var confirmLogout = false
    var body: some View {
        Form {
            Section("我的 NAS") {
                LabeledContent("账号", value: library.session?.username ?? "")
                Text(library.session?.base.absoluteString ?? "").font(.footnote).textSelection(.enabled)
            }
            Section("目录索引") {
                LabeledContent("歌曲", value: "\(library.tracks.count)")
                LabeledContent("已有路径", value: "\(library.tracks.count - library.missingPaths)")
                LabeledContent("路径请求失败", value: "\(library.pathFailures)")
                SyncStatus()
                Button("重新读取全部路径") { library.refresh(rebuildPaths: true) }.disabled(library.busy)
                Text("仅调用飞牛音乐的歌曲与元数据接口。不会安装 NAS 插件，也不会修改 NAS 文件。首次同步期间请保持 App 在前台。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("播放") {
                Toggle("通过 NAS 转码为 MP3", isOn: $player.useTranscode)
                Text("原音无法播放时开启，重新点选歌曲生效。转码由飞牛音乐提供，会消耗 NAS 资源。").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("退出账号", role: .destructive) { confirmLogout = true }
            }
            Section("关于牛听") {
                Text("0.1.0 · 独立开发的飞牛音乐客户端")
                Text("支持直连 NAS、最近添加、文件夹索引、搜索、播放队列和锁屏控制。当前不支持 FN Connect 中继、歌词、离线下载和文件管理。").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("设置")
        .confirmationDialog("退出并清除本机登录令牌？", isPresented: $confirmLogout) {
            Button("退出账号", role: .destructive) { player.stop(); library.logout() }
        }
    }
}

struct PlayerView: View {
    @EnvironmentObject var player: PlayerStore
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    private func timestamp(_ value: Double) -> String { let seconds = Int(max(0, value)); return String(format: "%d:%02d", seconds / 60, seconds % 60) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Image(systemName: "waveform").font(.system(size: 92, weight: .light)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 230)
                        .background(LinearGradient(colors: [.teal, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 32))
                    VStack(spacing: 8) {
                        Text(player.current?.title ?? "未在播放").font(.title2.bold()).multilineTextAlignment(.center)
                        Text(player.current?.artist ?? "").foregroundStyle(.secondary)
                    }
                    VStack {
                        Slider(value: Binding(get: { min(player.position, max(1, player.duration)) }, set: { player.seek($0) }), in: 0...max(1, player.duration)).disabled(player.duration <= 0)
                        HStack { Text(timestamp(player.position)); Spacer(); Text(timestamp(player.duration)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 40) {
                        Button { player.previous() } label: { Image(systemName: "backward.end.fill").font(.title) }.accessibilityLabel("上一首")
                        Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 72)) }.accessibilityLabel(player.playing ? "暂停" : "播放")
                        Button { player.next() } label: { Image(systemName: "forward.end.fill").font(.title) }.accessibilityLabel("下一首")
                    }
                    if player.loading { ProgressView("正在加载音频…") }
                    if let error = player.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                    if let song = player.current, !song.path.isEmpty { Text(song.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }.padding(28)
            }.navigationTitle("正在播放").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
