import Foundation

/// Uses the same public, read-only requests as the Yapern website.
nonisolated struct MessageAPI: Sendable {
    static let pageSize = 20

    private let session: URLSession
    private let baseURL: URL

    // This is the website's public browser key, not an owner or account key.
    private static let publicKey = "bff_pk_1f9bb9fd543d6a5476ad7ce210577c2479d290a5cdc06282de9eb884d57005c4"
    private static let projectID = "90da3093-84b6-4cd7-a39a-a8afc39403b8"

    init(session: URLSession = .shared, baseURL: URL = URL(string: "https://api.yapern.com")!) {
        self.session = session
        self.baseURL = baseURL
    }

    func fetchMessages(offset: Int, boardID: String? = nil) async throws -> [Message] {
        var query = [
            "select": "id,board_id,user_id,title,body,created_at",
            "order": "created_at.desc",
            "limit": String(Self.pageSize),
            "offset": String(offset),
        ]
        if let boardID { query["board_id"] = "eq.\(boardID)" }
        let messages: [Message] = try await readRows("messages", query: query)
        guard messages.allSatisfy({
            !$0.id.isEmpty && !$0.boardID.isEmpty && !$0.userID.isEmpty &&
                (boardID == nil || $0.boardID == boardID)
        }) else { throw MessageAPIError.invalidResponse }
        return messages
    }

    func fetchBoards() async throws -> [Board] {
        var boards: [Board] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            let page: [Board] = try await readRows("boards", query: [
                "select": "id,slug,name,description", "order": "slug.asc",
                "limit": "100", "offset": String(offset),
            ])
            guard page.allSatisfy({
                !$0.id.isEmpty && $0.slug.range(of: #"^[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?$"#, options: .regularExpression) != nil
            }) else { throw MessageAPIError.invalidResponse }
            boards.append(contentsOf: page)
            if page.count < 100 { return boards }
            offset += page.count
        }
    }

    func fetchAuthor(id: String) async throws -> String {
        let authors: [MessageAuthor] = try await readRows("users", query: [
            "select": "id,name", "id": "eq.\(id)", "limit": "1",
        ])
        guard let author = authors.first else { return "Unknown user" }
        guard author.id == id else { throw MessageAPIError.invalidResponse }
        let name = author.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unknown user" : name
    }

    func fetchReplies(messageID: String) async throws -> [Reply] {
        var replies: [Reply] = []
        var seen = Set<String>()
        var offset = 0
        while true {
            try Task.checkCancellation()
            let page: [Reply] = try await readRows("replies", query: [
                "select": "id,message_id,user_id,body,created_at",
                "message_id": "eq.\(messageID)", "order": "created_at.asc",
                "limit": "100", "offset": String(offset),
            ])
            guard page.allSatisfy({
                !$0.id.isEmpty && $0.messageID == messageID && !$0.userID.isEmpty &&
                    !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) else { throw MessageAPIError.invalidResponse }
            replies.append(contentsOf: page.filter { seen.insert($0.id).inserted })
            if page.count < 100 { return replies }
            offset += page.count
        }
    }

    private func readRows<Row: Decodable>(_ table: String, query: [String: String]) async throws -> [Row] {
        let url = baseURL.appending(path: "bff/data/\(Self.projectID)/tables/\(table)")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw MessageAPIError.invalidResponse
        }
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let requestURL = components.url else { throw MessageAPIError.invalidResponse }
        var request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue(Self.publicKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw MessageAPIError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw MessageAPIError.unavailable }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid message date")
        }
        do {
            let rows = try decoder.decode(Rows<Row>.self, from: data).data
            guard rows.count <= (Int(query["limit"] ?? "0") ?? 0) else {
                throw MessageAPIError.invalidResponse
            }
            return rows
        } catch is DecodingError {
            throw MessageAPIError.invalidResponse
        }
    }

    private struct Rows<Row: Decodable>: Decodable {
        let data: [Row]
    }
}

nonisolated enum MessageAPIError: LocalizedError {
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable: "Messages are unavailable right now. Please try again."
        case .invalidResponse: "Couldn’t load these messages. Please try again."
        }
    }
}
