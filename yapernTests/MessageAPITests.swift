import XCTest
@testable import yapern

final class MessageAPITests: XCTestCase {
    func testPublicFeedRequestFiltersPaginatesAndDecodesBothDateFormats() async throws {
        let session = makeStubSession { request in
            let query = request.query
            XCTAssertEqual(request.url!.scheme, "https")
            XCTAssertEqual(request.url!.host, "api.yapern.com")
            XCTAssertEqual(request.url!.path, "/tables/messages")
            XCTAssertNil(request.value(forHTTPHeaderField: "apikey"))
            XCTAssertNil(request.value(forHTTPHeaderField: "authorization"))
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(query["board_id"], "eq.apps")
            XCTAssertEqual(query["offset"], "20")
            XCTAssertEqual(query["limit"], "20")
            XCTAssertEqual(query["order"], "created_at.desc")
            return .rows([
                messageRow(id: "a", board: "apps"),
                messageRow(id: "b", board: "apps", date: "2026-10-19T06:19:59Z"),
            ])
        }
        defer { session.invalidateAndCancel() }
        let messages = try await MessageAPI(session: session).fetchMessages(offset: 20, boardID: "apps")
        XCTAssertEqual(messages.map(\.id), ["a", "b"])
        XCTAssertEqual(messages[0].createdAt.timeIntervalSince(messages[1].createdAt), 0.822, accuracy: 0.001)
    }

    func testBoardsUsePublicTableEndpoint() async throws {
        let session = makeStubSession { request in
            XCTAssertEqual(request.url!.path, "/tables/boards")
            XCTAssertNil(request.value(forHTTPHeaderField: "apikey"))
            XCTAssertEqual(request.query, [
                "select": "id,slug,name,description", "order": "slug.asc", "limit": "100", "offset": "0",
            ])
            return .rows([["id": "general", "slug": "general", "name": "General", "description": "Discussion"]])
        }
        defer { session.invalidateAndCancel() }
        let boards = try await MessageAPI(session: session).fetchBoards()
        XCTAssertEqual(boards.map(\.id), ["general"])
    }

    func testAuthorsUsePublicTableEndpoint() async throws {
        let session = makeStubSession { request in
            XCTAssertEqual(request.url!.path, "/tables/users")
            XCTAssertNil(request.value(forHTTPHeaderField: "apikey"))
            XCTAssertEqual(request.query, ["select": "id,name", "id": "eq.user", "limit": "1"])
            return .rows([["id": "user", "name": " Alex "]])
        }
        defer { session.invalidateAndCancel() }
        let name = try await MessageAPI(session: session).fetchAuthor(id: "user")
        XCTAssertEqual(name, "Alex")
    }

    func testRejectsWrongBoardInvalidDatesAndOversizedPages() async {
        for rows in [
            [messageRow(id: "a", board: "another-board")],
            [messageRow(id: "a", date: "not a date")],
            (0..<21).map { messageRow(id: String($0)) },
        ] {
            let session = makeStubSession { _ in .rows(rows) }
            do {
                _ = try await MessageAPI(session: session).fetchMessages(offset: 0, boardID: "general")
                XCTFail("Invalid response accepted")
            } catch {
                XCTAssertTrue(error is MessageAPIError)
            }
            session.invalidateAndCancel()
        }
    }

    func testRepliesReadAllPagesInChronologicalOrder() async throws {
        let session = makeStubSession { request in
            XCTAssertEqual(request.url!.path, "/tables/replies")
            XCTAssertNil(request.value(forHTTPHeaderField: "apikey"))
            XCTAssertEqual(request.query["message_id"], "eq.message")
            XCTAssertEqual(request.query["order"], "created_at.asc")
            let offset = Int(request.query["offset"]!)!
            let count = offset == 0 ? 100 : 1
            return .rows((offset..<(offset + count)).map { index in
                ["id": String(index), "message_id": "message", "user_id": "user", "body": "Reply \(index)", "created_at": "2026-10-19T06:19:59Z"]
            })
        }
        defer { session.invalidateAndCancel() }
        let replies = try await MessageAPI(session: session).fetchReplies(messageID: "message")
        XCTAssertEqual(replies.count, 101)
        XCTAssertEqual(replies.last?.id, "100")
    }
}

nonisolated struct StubResponse {
    let status: Int
    let data: Data
    var delay: TimeInterval = 0

    static func rows(_ values: [[String: String]], delay: TimeInterval = 0) -> StubResponse {
        StubResponse(status: 200, data: try! JSONSerialization.data(withJSONObject: ["data": values]), delay: delay)
    }
}

nonisolated final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((URLRequest) throws -> StubResponse)?
    private var work: DispatchWorkItem?

    static func install(_ handler: @escaping (URLRequest) throws -> StubResponse) {
        lock.lock()
        defer { lock.unlock() }
        Self.handler = handler
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        do {
            let result = try XCTUnwrap(handler)(request)
            let work = DispatchWorkItem { [self] in
                let response = HTTPURLResponse(url: request.url!, statusCode: result.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: result.data)
                client?.urlProtocolDidFinishLoading(self)
            }
            self.work = work
            DispatchQueue.global().asyncAfter(deadline: .now() + result.delay, execute: work)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() { work?.cancel() }
}

nonisolated func makeStubSession(_ handler: @escaping (URLRequest) throws -> StubResponse) -> URLSession {
    StubURLProtocol.install(handler)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

nonisolated func messageRow(id: String, board: String = "general", date: String = "2026-10-19T06:19:59.822Z") -> [String: String] {
    ["id": id, "board_id": board, "user_id": "user", "title": "Message \(id)", "body": "Body \(id)", "created_at": date]
}

nonisolated extension URLRequest {
    var query: [String: String] {
        Dictionary(uniqueKeysWithValues: URLComponents(url: url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
    }
}
