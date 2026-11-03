import XCTest
@testable import FeiniuLite

final class StubProtocol: URLProtocol {
    static var response: [String: Any] = [:]
    static var lastRequest: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: Self.response))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class APITests: XCTestCase {
    func api() -> MusicAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return MusicAPI(Session(base: URL(string: "https://nas.example")!, username: "test", token: "test-token"), configuration: config)
    }
    func testMetadataPathWithoutEnhancement() async throws {
        StubProtocol.response = ["code": 0, "data": ["audioSpec": ["path": "/Music/Jazz/song.flac"]]]
        let path = try await api().filePath(id: "song-1")
        XCTAssertEqual(path, "/Music/Jazz/song.flac")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/music/api/v1/track/metadata")
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Cookie"), "music-token=test-token")
    }
    func testRecentPageUsesServerCreationOrder() async throws {
        StubProtocol.response = ["code": 0, "data": ["list": [["guid": "one", "createdAt": 123]], "total": 201]]
        let (songs, total) = try await api().tracks(page: 2)
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(total, 201)
        let query = URLComponents(url: StubProtocol.lastRequest!.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "sort" }?.value, "createdAt,desc")
        XCTAssertEqual(query.first { $0.name == "page" }?.value, "2")
    }
    func testBusinessErrorIsNotReportedAsEmptyLibrary() async {
        StubProtocol.response = ["code": 403, "msg": "没有权限", "data": [:]]
        do { _ = try await api().tracks(page: 1); XCTFail("Expected server error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("没有权限")) }
    }
    func testMissingMetadataPathRemainsEmpty() async throws {
        StubProtocol.response = ["code": 0, "data": ["track": ["guid": "one", "title": "hello"]]]
        let path = try await api().filePath(id: "one")
        XCTAssertEqual(path, "")
    }
}
