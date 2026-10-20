import Foundation

nonisolated struct Message: Decodable, Hashable, Identifiable {
    let id: String
    let boardID: String
    let userID: String
    let title: String
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, body
        case boardID = "board_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

nonisolated struct Board: Decodable, Hashable, Identifiable {
    let id: String
    let slug: String
    let name: String
    let description: String
}

nonisolated struct Reply: Decodable, Hashable, Identifiable {
    let id: String
    let messageID: String
    let userID: String
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body
        case messageID = "message_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

nonisolated struct MessageAuthor: Decodable, Sendable {
    let id: String
    let name: String
}
