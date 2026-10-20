#if DEBUG
import Foundation

/// A local transport for UI tests. It is never compiled into release builds.
nonisolated final class UITestURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var state = State()

    private struct State {
        var name = "Alex"
        var expiredWrite = false
        var boards: [[String: String]] = [
            ["id": "general", "slug": "general", "name": "General", "description": "A place for everyday conversations."],
            ["id": "apps", "slug": "apps", "name": "Apps", "description": "Share what you’re building and using."],
        ]
        var messages: [[String: String]] = (0..<25).map { index in
            ["id": "message-\(index)", "board_id": index == 1 ? "apps" : "general", "user_id": index == 0 ? "user" : "other",
             "title": index == 0 ? "Welcome to Yapern" : "A conversation worth having \(index)",
             "body": "A little space to share ideas and hear another perspective. What have you been thinking about lately?",
             "created_at": "2026-10-20T09:00:00Z"]
        }
        var replies: [[String: String]] = []
    }

    static func makeAPI() -> MessageAPI {
        lock.lock()
        state = State()
        lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UITestURLProtocol.self]
        return MessageAPI(session: URLSession(configuration: configuration))
    }

    static var account: AccountSession {
        AccountSession(token: "bff_us_" + String(repeating: "a", count: 64),
                       session: .init(id: "session", userID: "user", expiresAt: Date.now.addingTimeInterval(86400)),
                       user: .init(id: "user", email: "alex@example.com"))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        if ProcessInfo.processInfo.arguments.contains("--ui-offline") {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        do {
            let (status, payload) = try Self.respond(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: payload))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    private static func respond(_ request: URLRequest) throws -> (Int, [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        let path = request.url!.path
        let method = request.httpMethod ?? "GET"
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
        }
        let body = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        if path.hasPrefix("/tables/"), method == "POST", !state.expiredWrite,
           ProcessInfo.processInfo.arguments.contains("--ui-expire-on-write") {
            state.expiredWrite = true
            return (401, ["error": "invalid_session"])
        }
        if path == "/auth/email" || path == "/auth/session" {
            if method == "DELETE" { return (200, ["revoked": true]) }
            return (200, ["token": account.token, "session": ["id": "session", "user_id": "user", "expires_at": "2099-01-01T00:00:00Z"],
                          "user": ["id": "user", "email": "alex@example.com"]])
        }
        if path == "/og-image" { return (200, ["status": "failed", "image": NSNull()]) }
        if path == "/tables/users" {
            if method == "PATCH" { state.name = body["name"] ?? state.name }
            let id = String((query["id"] ?? "eq.user").dropFirst(3))
            return (200, ["data": [["id": id, "name": id == "user" ? state.name : "Taylor"]]])
        }
        if method == "POST" {
            var row = body
            row["id"] = UUID().uuidString
            row["created_at"] = "2026-10-20T10:00:00Z"
            switch path {
            case "/tables/boards": state.boards.append(row)
            case "/tables/messages": state.messages.insert(row, at: 0)
            case "/tables/replies": state.replies.append(row)
            default: return (404, ["error": "not_found"])
            }
            return (201, ["data": [row]])
        }
        if path == "/tables/messages", method == "DELETE" {
            let id = String((query["id"] ?? "").dropFirst(3))
            let count = state.messages.count
            state.messages.removeAll { $0["id"] == id }
            state.replies.removeAll { $0["message_id"] == id }
            return (200, ["data": [], "meta": ["changes": count - state.messages.count]])
        }
        var rows: [[String: String]]
        switch path {
        case "/tables/boards": rows = state.boards.sorted { $0["slug"]! < $1["slug"]! }
        case "/tables/messages": rows = state.messages
        case "/tables/replies": rows = state.replies
        default: return (404, ["error": "not_found"])
        }
        for key in ["board_id", "message_id", "id"] {
            if let filter = query[key] { rows = rows.filter { $0[key] == String(filter.dropFirst(3)) } }
        }
        let offset = Int(query["offset"] ?? "0") ?? 0
        let limit = Int(query["limit"] ?? "100") ?? 100
        return (200, ["data": Array(rows.dropFirst(offset).prefix(limit))])
    }
}

@MainActor final class UITestSessionStorage: SessionStorage {
    private var data: Data?
    init(signedIn: Bool) { data = signedIn ? try? JSONEncoder().encode(UITestURLProtocol.account) : nil }
    func read() throws -> Data? { data }
    func write(_ data: Data?) throws { self.data = data }
}
#endif
