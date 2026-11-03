import Foundation

struct Track: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var path: String
    var createdAt: Double

    init(_ json: [String: Any]) {
        id = json["guid"] as? String ?? ""
        title = json["title"] as? String ?? "未命名歌曲"
        artist = (json["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: " / ")
        album = (json["album"] as? [String: Any])?["name"] as? String ?? ""
        path = Self.filePath(json)
        createdAt = (json["createdAt"] as? NSNumber)?.doubleValue ?? Double(json["createdAt"] as? String ?? "") ?? 0
    }

    static func filePath(_ json: [String: Any]) -> String {
        let spec = json["audioSpec"] as? [String: Any]
        return spec?["path"] as? String ?? ""
    }

    var components: [String] { path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init) }
}

struct FolderEntry: Identifiable {
    let parts: [String]
    let count: Int
    var id: String { parts.joined(separator: "/") }
    var name: String { parts.last ?? "文件夹" }
}

enum FolderIndex {
    static func folders(_ tracks: [Track], at prefix: [String]) -> [FolderEntry] {
        var counts: [String: Int] = [:]
        for track in tracks {
            let parts = track.components
            guard parts.count > prefix.count + 1, Array(parts.prefix(prefix.count)) == prefix else { continue }
            counts[parts[prefix.count], default: 0] += 1
        }
        return counts.map { FolderEntry(parts: prefix + [$0.key], count: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func songs(_ tracks: [Track], at prefix: [String]) -> [Track] {
        tracks.filter { !$0.path.isEmpty && Array($0.components.dropLast()) == prefix }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

struct MusicError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct Session: Codable {
    let base: URL
    let username: String
    let token: String
}
