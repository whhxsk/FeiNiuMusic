import Foundation
import CryptoKit
import Security

enum Keychain {
    private static let service = "com.whhxsk.feiniulite.session"
    static func read() -> Session? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "session", kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }
    static func save(_ session: Session) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "session"]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw MusicError(message: "无法更新安全登录凭据") }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw MusicError(message: "无法保存安全登录凭据") }
    }
    static func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}

final class SafeRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let from = response.url, let to = request.url,
              from.scheme == to.scheme, from.host == to.host, from.port == to.port else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

final class MusicAPI {
    let session: Session
    private let client: URLSession
    init(_ session: Session, configuration: URLSessionConfiguration? = nil) {
        self.session = session
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 60
        client = URLSession(configuration: config, delegate: SafeRedirects(), delegateQueue: nil)
    }
    static func serverURL(_ text: String) throws -> URL {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") { value = "http://" + value }
        guard var parts = URLComponents(string: value), ["http", "https"].contains(parts.scheme ?? ""),
              parts.host != nil, parts.user == nil, parts.password == nil else {
            throw MusicError(message: "请输入完整 NAS 地址，例如 http://192.168.1.10:5666")
        }
        if parts.query != nil || parts.fragment != nil { throw MusicError(message: "请填写 NAS 地址，不要填写带参数的分享链接") }
        let path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path == "music" || path == "music/api/v1" { parts.path = "" }
        else if !path.isEmpty { throw MusicError(message: "请填写 NAS 根地址，不包含页面路径") }
        guard let url = parts.url else { throw MusicError(message: "服务器地址无效") }
        return url
    }
    func url(_ path: String, query: [String: String] = [:]) -> URL {
        var parts = URLComponents(url: session.base.appendingPathComponent("music/api/v1" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return parts.url!
    }
    var cookie: HTTPCookie? {
        HTTPCookie(properties: [.name: "music-token", .value: session.token,
            .domain: session.base.host ?? "", .path: "/", .secure: session.base.scheme == "https" ? "TRUE" : "FALSE"])
    }
    func request(_ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: url(path, query: query))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !session.token.isEmpty { request.setValue("music-token=\(session.token)", forHTTPHeaderField: "Cookie") }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await client.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw MusicError(message: "服务器没有返回 HTTP 响应") }
        guard (200..<300).contains(response.statusCode) else {
            throw MusicError(message: "请求失败 HTTP \(response.statusCode)。请确认地址、端口和账号权限。")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let code = json["code"] as? Int else {
            throw MusicError(message: "地址返回的不是飞牛音乐接口，请检查 NAS 地址与端口")
        }
        guard code == 0 else {
            throw MusicError(message: code == 120001 ? "账号或密码错误" : "飞牛返回 \(code)：\(json["msg"] as? String ?? "请重新登录或检查权限")")
        }
        guard let payload = json["data"] as? [String: Any] else { throw MusicError(message: "服务器响应缺少 data") }
        return payload
    }
    static func login(address: String, username: String, password: String) async throws -> Session {
        let base = try serverURL(address)
        let client = MusicAPI(Session(base: base, username: username, token: ""))
        let device = UserDefaults.standard.string(forKey: "deviceID") ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(device, forKey: "deviceID")
        let digest = SHA256.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined()
        let response = try await client.request("/user/password-login", body: ["username": username, "password": digest, "deviceId": device])
        guard let token = response["userToken"] as? String, !token.isEmpty else { throw MusicError(message: "登录响应缺少令牌") }
        return Session(base: base, username: username, token: token)
    }
    func tracks(page: Int) async throws -> ([Track], Int) {
        let data = try await request("/track/list", query: ["page": "\(page)", "size": "200", "sort": "createdAt,desc"])
        guard let rows = data["list"] as? [[String: Any]] else { throw MusicError(message: "歌曲列表格式不兼容") }
        return (rows.map(Track.init).filter { !$0.id.isEmpty }, (data["total"] as? NSNumber)?.intValue ?? rows.count)
    }
    func filePath(id: String) async throws -> String {
        let data = try await request("/track/metadata", query: ["guid": id])
        let direct = Track.filePath(data)
        if !direct.isEmpty { return direct }
        return Track.filePath(data["track"] as? [String: Any] ?? [:])
    }
}
