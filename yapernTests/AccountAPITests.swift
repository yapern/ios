import XCTest
@testable import yapern

final class AccountAPITests: XCTestCase {
    func testEmailSignInNormalizesEmailAndValidatesSession() async throws {
        let session = makeStubSession { request in
            XCTAssertEqual(request.url?.path, "/auth/email")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "authorization"))
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(try request.jsonBody(), ["email": "alex@example.com", "password": "a password"])
            return .json(authPayload())
        }
        defer { session.invalidateAndCancel() }
        let account = try await MessageAPI(session: session).signIn(email: " Alex@Example.com ", password: "a password")
        XCTAssertTrue(account.isValid)
        XCTAssertEqual(account.user.id, "user")
    }

    func testRejectsMismatchedOrExpiredSessionIdentity() async {
        for (id, expiry) in [("another-user", "2099-01-01T00:00:00Z"), ("user", "2000-01-01T00:00:00Z")] {
            let session = makeStubSession { _ in .json(authPayload(userID: id, expiry: expiry)) }
            do {
                _ = try await MessageAPI(session: session).signIn(email: "alex@example.com", password: "password")
                XCTFail("Invalid session accepted")
            } catch { XCTAssertTrue(error is MessageAPIError) }
            session.invalidateAndCancel()
        }
    }

    func testProfileUpdatesAreAuthenticatedAndMustMatchSavedName() async throws {
        let session = makeStubSession { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/tables/users")
            XCTAssertEqual(request.query, ["id": "eq.user"])
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer \(testToken)")
            XCTAssertEqual(try request.jsonBody(), ["name": "Alex"])
            return .rows([["id": "user", "name": "Alex"]])
        }
        defer { session.invalidateAndCancel() }
        let api = MessageAPI(session: session)
        let profile = try await api.updateName(" Alex ", current: testAccount())
        XCTAssertEqual(profile.name, "Alex")
        StubURLProtocol.install { _ in .rows([["id": "user", "name": "Other"]]) }
        do {
            _ = try await api.updateName("Alex", current: testAccount())
            XCTFail("Unconfirmed profile change accepted")
        } catch { XCTAssertTrue(error is MessageAPIError) }
    }

    func testCreationUsesWebsitePayloadsAndValidatesOwnership() async throws {
        let session = makeStubSession { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer \(testToken)")
            let body = try request.jsonBody()
            XCTAssertEqual(body["user_id"], "user")
            switch request.url!.path {
            case "/tables/boards":
                XCTAssertEqual(body, ["user_id": "user", "name": "New Board", "slug": "new-board", "description": "Discussion"])
                return .rows([body.merging(["id": "board"]) { _, new in new }])
            case "/tables/messages":
                XCTAssertEqual(body, ["user_id": "user", "board_id": "board", "title": "Hello", "body": "Text"])
                return .rows([body.merging(["id": "post", "created_at": "2026-10-20T09:00:00Z"]) { _, new in new }])
            default:
                XCTAssertEqual(request.url!.path, "/tables/replies")
                XCTAssertEqual(body, ["user_id": "user", "message_id": "post", "body": "Reply"])
                return .rows([body.merging(["id": "reply", "created_at": "2026-10-20T09:00:00Z"]) { _, new in new }])
            }
        }
        defer { session.invalidateAndCancel() }
        let api = MessageAPI(session: session)
        let board = try await api.createBoard(name: " New Board ", description: " Discussion ", current: testAccount())
        let message = try await api.createMessage(boardID: "board", title: " Hello ", body: " Text ", current: testAccount())
        let reply = try await api.createReply(messageID: "post", body: " Reply ", current: testAccount())
        XCTAssertEqual(board.slug, "new-board")
        XCTAssertEqual(message.id, "post")
        XCTAssertEqual(reply.id, "reply")
        StubURLProtocol.install { _ in .rows([messageRow(id: "wrong", board: "board").merging(["user_id": "someone-else"]) { _, new in new }]) }
        do {
            _ = try await api.createMessage(boardID: "board", title: "Hello", body: "Text", current: testAccount())
            XCTFail("Wrong author accepted")
        } catch { XCTAssertTrue(error is MessageAPIError) }
    }

    func testInvalidDraftsNeverSendRequests() async {
        let session = makeStubSession { _ in XCTFail("Unexpected request"); return .rows([]) }
        defer { session.invalidateAndCancel() }
        let api = MessageAPI(session: session)
        do {
            _ = try await api.createReply(messageID: "post", body: String(repeating: "👋", count: 1001), current: testAccount())
            XCTFail("Overlong UTF-16 body accepted")
        } catch {}
        do {
            _ = try await api.createBoard(name: "Not/valid", description: "", current: testAccount())
            XCTFail("Invalid slug accepted")
        } catch {}
    }

    func testDeleteFiltersOwnershipAndRequiresExactlyOneDeletedMessage() async throws {
        let message = try MessageAPI.makeDecoder().decode(Message.self, from: JSONSerialization.data(withJSONObject: messageRow(id: "post")))
        let session = makeStubSession { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/tables/messages")
            XCTAssertEqual(request.query, ["id": "eq.post", "board_id": "eq.general", "user_id": "eq.user"])
            return .json(["data": [], "meta": ["changes": 1]])
        }
        defer { session.invalidateAndCancel() }
        let api = MessageAPI(session: session)
        try await api.deleteMessage(message, current: testAccount())
        StubURLProtocol.install { _ in .json(["data": [], "meta": ["changes": 0]]) }
        do {
            try await api.deleteMessage(message, current: testAccount())
            XCTFail("Unconfirmed deletion accepted")
        } catch { XCTAssertTrue(error is MessageAPIError) }
    }

    func testPreviewReadyAndFailedResponsesAndUnsafePollingURL() async throws {
        let session = makeStubSession { request in
            XCTAssertEqual(request.url?.path, "/og-image")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(try request.jsonBody(), ["url": "https://example.com/article"])
            return .json(["status": "ready", "image": "https://cdn.example.com/preview"])
        }
        defer { session.invalidateAndCancel() }
        let api = MessageAPI(session: session)
        let url = URL(string: "https://example.com/article")!
        let image = try await api.fetchPreview(url: url, current: testAccount())
        XCTAssertEqual(image?.absoluteString, "https://cdn.example.com/preview")
        StubURLProtocol.install { _ in .json(["status": "failed", "image": NSNull()]) }
        let unavailable = try await api.fetchPreview(url: url, current: testAccount())
        XCTAssertNil(unavailable)
        StubURLProtocol.install { _ in .json(["status": "pending", "previewId": "6cfc6328-7b56-4216-8e63-161774b2824f", "statusUrl": "https://evil.example/previews/6cfc6328-7b56-4216-8e63-161774b2824f"], status: 202) }
        do {
            _ = try await api.fetchPreview(url: url, current: testAccount())
            XCTFail("Unsafe status URL accepted")
        } catch { XCTAssertTrue(error is MessageAPIError) }
    }

    func testDraftSerializationMatchesWebAndRejectsUnsafeURLs() {
        XCTAssertEqual(MessageDraft.body(text: " Body ", link: " https://example.com ", image: URL(string: "https://cdn.example.com/image")),
                       "https://cdn.example.com/image\nhttps://example.com\n\nBody")
        XCTAssertEqual(MessageDraft.body(text: "", link: "https://example.com"), "https://example.com")
        for value in ["example.com", "javascript:alert(1)", "https://name:password@example.com", "file:///tmp/image"] {
            XCTAssertNil(MessageDraft.webURL(value))
        }
    }
}

@MainActor
final class AccountStoreTests: XCTestCase {
    func testRestoresSecureSessionAndKeepsItOnNetworkFailure() async throws {
        let storage = MemorySessionStorage()
        try storage.write(JSONEncoder().encode(testAccount()))
        let session = makeStubSession { _ in throw URLError(.notConnectedToInternet) }
        defer { session.invalidateAndCancel() }
        let store = AccountStore(api: MessageAPI(session: session), storage: storage)
        XCTAssertTrue(store.isSignedIn)
        await store.validateSession()
        XCTAssertTrue(store.isSignedIn)
        XCTAssertNotNil(storage.data)
        XCTAssertNotNil(store.sessionError)
        do { try await store.signOut(); XCTFail("Network failure ignored") } catch {}
        XCTAssertTrue(store.isSignedIn)
        XCTAssertNotNil(storage.data)
    }

    func testUnauthorizedWriteClearsMemoryAndSecureSession() async throws {
        let storage = MemorySessionStorage()
        try storage.write(JSONEncoder().encode(testAccount()))
        let session = makeStubSession { _ in .json(["error": "invalid_session"], status: 401) }
        defer { session.invalidateAndCancel() }
        let store = AccountStore(api: MessageAPI(session: session), storage: storage)
        do {
            try await store.saveName("Alex")
            XCTFail("Unauthorized write accepted")
        } catch { XCTAssertTrue(error is MessageAPIError) }
        XCTAssertFalse(store.isSignedIn)
        XCTAssertNil(storage.data)
    }

    func testSignOutRevokesSessionAndRemovesSavedCredentials() async throws {
        let storage = MemorySessionStorage()
        try storage.write(JSONEncoder().encode(testAccount()))
        let session = makeStubSession { request in
            XCTAssertEqual(request.url?.path, "/auth/session")
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer \(testToken)")
            return .json(["revoked": true])
        }
        defer { session.invalidateAndCancel() }
        let store = AccountStore(api: MessageAPI(session: session), storage: storage)
        try await store.signOut()
        XCTAssertFalse(store.isSignedIn)
        XCTAssertNil(storage.data)
    }

    func testSuccessfulSignInPersistsSessionWithoutPassword() async throws {
        let storage = MemorySessionStorage()
        let session = makeStubSession { _ in .json(authPayload()) }
        defer { session.invalidateAndCancel() }
        let store = AccountStore(api: MessageAPI(session: session), storage: storage)
        try await store.signIn(email: "alex@example.com", password: "private password")
        XCTAssertTrue(store.isSignedIn)
        let data = try XCTUnwrap(storage.data)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private password"))
        let restored = AccountStore(api: MessageAPI(session: session), storage: storage)
        XCTAssertEqual(restored.session, store.session)
    }
}

@MainActor private final class MemorySessionStorage: SessionStorage {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ data: Data?) throws { self.data = data }
}

nonisolated private let testToken = "bff_us_" + String(repeating: "a", count: 64)
nonisolated private func testAccount() -> AccountSession {
    try! MessageAPI.makeDecoder().decode(AccountSession.self, from: JSONSerialization.data(withJSONObject: authPayload()))
}
nonisolated private func authPayload(userID: String = "user", expiry: String = "2099-01-01T00:00:00Z") -> [String: Any] {
    ["token": testToken, "session": ["id": "session", "user_id": "user", "expires_at": expiry], "user": ["id": userID, "email": "alex@example.com"]]
}
nonisolated extension StubResponse {
    static func json(_ value: Any, status: Int = 200) -> StubResponse {
        StubResponse(status: status, data: try! JSONSerialization.data(withJSONObject: value))
    }
}
nonisolated private extension URLRequest {
    func jsonBody() throws -> [String: String] {
        var data = httpBody ?? Data()
        if data.isEmpty, let stream = httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
        }
        return try JSONDecoder().decode([String: String].self, from: data)
    }
}
