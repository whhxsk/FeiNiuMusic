import XCTest
@testable import FeiniuLite

final class CoreTests: XCTestCase {
    func track(_ id: String, _ path: String, created: Any = 0) -> Track {
        Track(["guid": id, "title": id, "audioSpec": ["path": path], "createdAt": created])
    }
    func testNestedDirectoriesAndDirectSongs() {
        let tracks = [track("one", "/Music/Jazz/a.flac"), track("two", "/Music/Jazz/Live/b.mp3"), track("three", "/Music/Pop/c.mp3")]
        let root = FolderIndex.folders(tracks, at: [])
        XCTAssertEqual(root.map(\.name), ["Music"])
        XCTAssertEqual(root.first?.count, 3)
        XCTAssertEqual(FolderIndex.songs(tracks, at: ["Music", "Jazz"]).map(\.id), ["one"])
        XCTAssertEqual(FolderIndex.folders(tracks, at: ["Music", "Jazz"]).map(\.name), ["Live"])
    }
    func testSiblingPrefixDoesNotLeakIntoFolder() {
        let tracks = [track("a", "/Music/AB/a.mp3"), track("b", "/Music/A/b.mp3")]
        XCTAssertEqual(FolderIndex.songs(tracks, at: ["Music", "A"]).map(\.id), ["b"])
    }
    func testMissingPathIsNotInvented() {
        let songs = [track("a", ""), Track(["guid": "b", "album": ["name": "不是文件夹"]])]
        XCTAssertTrue(FolderIndex.folders(songs, at: []).isEmpty)
        XCTAssertTrue(FolderIndex.songs(songs, at: []).isEmpty)
    }
    func testChineseAndBackslashPaths() {
        let songs = [track("a", "音乐\\周杰伦\\稻香.flac")]
        XCTAssertEqual(FolderIndex.folders(songs, at: ["音乐"]).first?.name, "周杰伦")
        XCTAssertEqual(FolderIndex.songs(songs, at: ["音乐", "周杰伦"]).count, 1)
    }
    func testCueTracksSharingAFileArePreserved() {
        let songs = [track("track1", "/Music/disc.flac"), track("track2", "/Music/disc.flac")]
        XCTAssertEqual(FolderIndex.songs(songs, at: ["Music"]).count, 2)
    }
    func testServerNormalization() throws {
        XCTAssertEqual(try MusicAPI.serverURL(" 192.168.1.5:5666 ").host, "192.168.1.5")
        XCTAssertEqual(try MusicAPI.serverURL("https://nas.example/music/api/v1/").path, "")
        XCTAssertThrowsError(try MusicAPI.serverURL("ftp://nas.example"))
        XCTAssertThrowsError(try MusicAPI.serverURL("https://name:password@nas.example"))
        XCTAssertThrowsError(try MusicAPI.serverURL("https://nas.example/?token=abc"))
    }
    func testCreationTimeSupportsStringAndNumber() {
        XCTAssertEqual(track("a", "", created: "1700000000000").createdAt, 1700000000000)
        XCTAssertEqual(track("b", "", created: 1700000000001).createdAt, 1700000000001)
    }
    func testAPIURLQueryEscapingAndCookieScope() {
        let api = MusicAPI(Session(base: URL(string: "https://nas.example:5667")!, username: "test", token: "secret"))
        let url = api.url("/track/metadata", query: ["guid": "a&b=1"])
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "a&b=1")
        XCTAssertEqual(url.path, "/music/api/v1/track/metadata")
        XCTAssertEqual(api.cookie?.domain, "nas.example")
        XCTAssertEqual(api.cookie?.isSecure, true)
    }
}
