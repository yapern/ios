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

/// Keeps each detail tied to the feed that opened it, including board feeds.
nonisolated struct MessageRoute: Hashable {
    let message: Message
    let store: FeedStore

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.message == rhs.message && lhs.store === rhs.store }
    func hash(into hasher: inout Hasher) {
        hasher.combine(message)
        hasher.combine(ObjectIdentifier(store))
    }
}
