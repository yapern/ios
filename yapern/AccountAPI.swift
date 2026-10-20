import Foundation

nonisolated struct AccountSession: Codable, Sendable, Equatable {
    let token: String
    let session: Details
    let user: User

    struct Details: Codable, Sendable, Equatable {
        let id: String
        let userID: String
        let expiresAt: Date
        enum CodingKeys: String, CodingKey {
            case id
            case userID = "user_id"
            case expiresAt = "expires_at"
        }
    }

    struct User: Codable, Sendable, Equatable {
        let id: String
        let email: String
    }

    var isValid: Bool {
        token.range(of: #"^bff_us_[a-f0-9]{64}$"#, options: .regularExpression) != nil &&
            !session.id.isEmpty && !user.id.isEmpty && session.userID == user.id &&
            !user.email.isEmpty && session.expiresAt > .now
    }
}

nonisolated extension MessageAPI {
    func send(path: String, method: String = "GET", query: [String: String] = [:],
              token: String? = nil, body: [String: String]? = nil,
              timeout: TimeInterval = 15) async throws -> (Data, HTTPURLResponse) {
        let url = baseURL.appending(path: path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw MessageAPIError.invalidResponse
        }
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let requestURL = components.url else { throw MessageAPIError.invalidResponse }
        var request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw MessageAPIError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let code = (try? JSONDecoder().decode(APIProblem.self, from: data))?.error
            switch code {
            case "invalid_credentials": throw MessageAPIError.notice("Email or password is incorrect.")
            case "weak_password": throw MessageAPIError.notice("Use at least 8 characters for a new password.")
            case "rate_limited": throw MessageAPIError.notice("Too many attempts. Wait a minute and try again.")
            case "session_limit": throw MessageAPIError.notice("Sign-in is busy. Please try again later.")
            default: break
            }
            switch response.statusCode {
            case 401: throw MessageAPIError.sessionExpired
            case 403: throw MessageAPIError.forbidden
            case 409: throw MessageAPIError.notice("A sub-yap with that name already exists. Choose another name.")
            case 400: throw MessageAPIError.notice("Check your details and try again.")
            default: throw MessageAPIError.unavailable
            }
        }
        return (data, response)
    }

    func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do { return try Self.makeDecoder().decode(type, from: data) }
        catch { throw MessageAPIError.invalidResponse }
    }

    func signIn(email: String, password: String) async throws -> AccountSession {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), email.utf16.count <= 254, !password.isEmpty, password.utf16.count <= 128 else {
            throw MessageAPIError.notice("Enter a valid email and a password of no more than 128 characters.")
        }
        let (data, _) = try await send(path: "auth/email", method: "POST", body: ["email": email, "password": password])
        let result = try decode(AccountSession.self, from: data)
        guard result.isValid else { throw MessageAPIError.invalidResponse }
        return result
    }

    func checkSession(_ current: AccountSession) async throws -> AccountSession {
        struct Result: Decodable { let session: AccountSession.Details; let user: AccountSession.User }
        let (data, _) = try await send(path: "auth/session", token: current.token)
        let result = try decode(Result.self, from: data)
        let updated = AccountSession(token: current.token, session: result.session, user: result.user)
        guard updated.isValid, updated.user.id == current.user.id else { throw MessageAPIError.invalidResponse }
        return updated
    }

    func signOut(_ current: AccountSession) async throws {
        struct Result: Decodable { let revoked: Bool }
        let (data, _) = try await send(path: "auth/session", method: "DELETE", token: current.token)
        guard try decode(Result.self, from: data).revoked else { throw MessageAPIError.invalidResponse }
    }

    func fetchProfile(_ current: AccountSession) async throws -> MessageAuthor {
        let (data, _) = try await send(path: "tables/users", query: [
            "select": "id,name", "id": "eq.\(current.user.id)", "limit": "1",
        ], token: current.token)
        let rows = try decode(TableRows<MessageAuthor>.self, from: data).data
        guard rows.count == 1, let profile = rows.first, profile.id == current.user.id else {
            throw MessageAPIError.invalidResponse
        }
        return profile
    }

    func updateName(_ name: String, current: AccountSession) async throws -> MessageAuthor {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf16.count <= 80 else {
            throw MessageAPIError.notice("Enter a name of 1–80 characters.")
        }
        return try await writeRow("users", method: "PATCH", query: ["id": "eq.\(current.user.id)"],
                                  values: ["name": name], current: current)
    }

    func createBoard(name: String, description: String, current: AccountSession) async throws -> Board {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = name.lowercased().replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
        guard !name.isEmpty, name.utf16.count <= 80, description.utf16.count <= 2000,
              slug.range(of: #"^[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?$"#, options: .regularExpression) != nil else {
            throw MessageAPIError.notice("Use 1–80 letters, numbers, spaces, or hyphens for the name, starting and ending with a letter or number.")
        }
        return try await writeRow("boards", values: ["name": name, "slug": slug, "description": description,
                                                     "user_id": current.user.id], current: current)
    }

    func createMessage(boardID: String, title: String, body: String, current: AccountSession) async throws -> Message {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !boardID.isEmpty, !title.isEmpty, title.utf16.count <= 200, !body.isEmpty, body.utf16.count <= 2000 else {
            throw MessageAPIError.notice("Choose a sub-yap, a title of 1–200 characters, and a message of 1–2000 characters.")
        }
        return try await writeRow("messages", values: ["board_id": boardID, "title": title, "body": body,
                                                       "user_id": current.user.id], current: current)
    }

    func createReply(messageID: String, body: String, current: AccountSession) async throws -> Reply {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageID.isEmpty, !body.isEmpty, body.utf16.count <= 2000 else {
            throw MessageAPIError.notice("Enter a reply of 1–2000 characters.")
        }
        return try await writeRow("replies", values: ["message_id": messageID, "body": body,
                                                      "user_id": current.user.id], current: current)
    }

    func deleteMessage(_ message: Message, current: AccountSession) async throws {
        guard message.userID == current.user.id else { throw MessageAPIError.forbidden }
        let (data, _) = try await send(path: "tables/messages", method: "DELETE", query: [
            "id": "eq.\(message.id)", "board_id": "eq.\(message.boardID)", "user_id": "eq.\(current.user.id)",
        ], token: current.token)
        struct Result: Decodable {
            let data: [Message]
            let meta: Meta
            struct Meta: Decodable { let changes: Int }
        }
        let result = try decode(Result.self, from: data)
        guard result.data.isEmpty, result.meta.changes == 1 else {
            throw MessageAPIError.notice("Could not confirm deletion. Reload the messages before trying again.")
        }
    }

    func fetchPreview(url: URL, current: AccountSession) async throws -> URL? {
        struct Preview: Decodable {
            let status: String?
            let image: String?
            let previewId: String?
            let statusUrl: String?
        }
        let deadline = Date.now.addingTimeInterval(45)
        var path = "og-image"
        var previewID: String?
        var method = "POST"
        while true {
            try Task.checkCancellation()
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw URLError(.timedOut) }
            let (data, response) = try await send(path: path, method: method, token: current.token,
                                                  body: method == "POST" ? ["url": url.absoluteString] : nil,
                                                  timeout: remaining)
            let preview = try decode(Preview.self, from: data)
            if response.statusCode == 200 {
                guard preview.status == nil || ["ready", "failed"].contains(preview.status!) else {
                    throw MessageAPIError.invalidResponse
                }
                return preview.image.flatMap(MessageDraft.webURL)
            }
            guard response.statusCode == 202, preview.status == "pending", let id = preview.previewId,
                  UUID(uuidString: id) != nil, previewID == nil || previewID == id,
                  let statusURL = preview.statusUrl.flatMap(URL.init(string:)),
                  statusURL.scheme == baseURL.scheme, statusURL.host == baseURL.host, statusURL.port == baseURL.port,
                  statusURL.user == nil, statusURL.password == nil, statusURL.query == nil, statusURL.fragment == nil,
                  statusURL.path == baseURL.appending(path: "previews/\(id)").path else {
                throw MessageAPIError.invalidResponse
            }
            previewID = id
            path = "previews/\(id)"
            method = "GET"
            let retry = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "1") ?? 1
            try await Task.sleep(for: .seconds(max(0.2, min(retry, 3, deadline.timeIntervalSinceNow))))
        }
    }

    private func writeRow<Row: Decodable>(_ table: String, method: String = "POST", query: [String: String] = [:],
                                          values: [String: String], current: AccountSession) async throws -> Row {
        let (data, _) = try await send(path: "tables/\(table)", method: method, query: query,
                                      token: current.token, body: values)
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = payload["data"] as? [[String: Any]], rows.count == 1, let row = rows.first,
              let id = row["id"] as? String, !id.isEmpty,
              (table != "users" || id == current.user.id),
              values.allSatisfy({ row[$0.key] as? String == $0.value }) else {
            throw MessageAPIError.notice("Could not confirm the change. Reload before trying again.")
        }
        guard let row = try decode(TableRows<Row>.self, from: data).data.first else { throw MessageAPIError.invalidResponse }
        return row
    }
}

nonisolated private struct APIProblem: Decodable { let error: String }
nonisolated private struct TableRows<Row: Decodable>: Decodable { let data: [Row] }

nonisolated enum MessageDraft {
    static func webURL(_ value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func body(text: String, link: String = "", image: URL? = nil) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let linked = link.isEmpty ? text : (text.isEmpty ? link : "\(link)\n\n\(text)")
        return image.map { "\($0.absoluteString)\n\(linked)" } ?? linked
    }
}
