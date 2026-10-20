import XCTest
@testable import yapern

@MainActor
final class FeedStoreTests: XCTestCase {
    func testPaginationDeduplicatesOverlapsAndStopsAtLastPage() async {
        let session = makeStubSession { request in
            switch request.url!.lastPathComponent {
            case "messages":
                return request.query["offset"] == "0"
                    ? .rows((0..<20).map { messageRow(id: String($0)) })
                    : .rows([messageRow(id: "19"), messageRow(id: "20"), messageRow(id: "21")])
            case "users": return .rows([["id": "user", "name": " Alex "]])
            default: return .rows([["id": "general", "slug": "general", "name": "General", "description": "Discussion"]])
            }
        }
        defer { session.invalidateAndCancel() }
        let store = FeedStore(api: MessageAPI(session: session))
        await store.loadIfNeeded()
        XCTAssertEqual(store.messages.count, 20)
        XCTAssertEqual(store.authorName(for: "user"), "Alex")
        XCTAssertTrue(store.canLoadMore)
        await store.loadMore()
        XCTAssertEqual(store.messages.count, 22)
        XCTAssertEqual(Set(store.messages.map(\.id)).count, 22)
        XCTAssertFalse(store.canLoadMore)
        XCTAssertEqual(store.messageURL(for: store.messages[0])?.absoluteString, "https://yapern.com/y/general/0")
    }

    func testRefreshFailureKeepsReadableMessagesAndRetryRecovers() async {
        let session = makeStubSession { request in
            request.url!.lastPathComponent == "messages" ? .rows([messageRow(id: "first")]) : .rows([])
        }
        defer { session.invalidateAndCancel() }
        let store = FeedStore(api: MessageAPI(session: session))
        await store.refresh()
        StubURLProtocol.install { _ in throw URLError(.notConnectedToInternet) }
        await store.refresh()
        XCTAssertEqual(store.messages.map(\.id), ["first"])
        XCTAssertTrue(store.errorMessage?.contains("offline") == true)
        XCTAssertFalse(store.isRefreshing)
        StubURLProtocol.install { request in
            request.url!.lastPathComponent == "messages" ? .rows([messageRow(id: "new")]) : .rows([])
        }
        await store.refresh()
        XCTAssertEqual(store.messages.map(\.id), ["new"])
        XCTAssertNil(store.errorMessage)
    }

    func testMetadataFailuresDoNotHideFeed() async {
        let session = makeStubSession { request in
            guard request.url!.lastPathComponent == "messages" else { throw URLError(.timedOut) }
            return .rows([messageRow(id: "first")])
        }
        defer { session.invalidateAndCancel() }
        let store = FeedStore(api: MessageAPI(session: session))
        await store.refresh()
        XCTAssertEqual(store.messages.count, 1)
        XCTAssertTrue(store.boards.isEmpty)
        XCTAssertEqual(store.authorName(for: "user"), "Name unavailable")
        XCTAssertNil(store.errorMessage)
    }

    func testFailedPageCanRetryWithoutSkippingMessages() async {
        let session = makeStubSession { request in
            guard request.url!.lastPathComponent == "messages" else { return .rows([]) }
            if request.query["offset"] == "20" { throw URLError(.timedOut) }
            return .rows((0..<20).map { messageRow(id: String($0)) })
        }
        defer { session.invalidateAndCancel() }
        let store = FeedStore(api: MessageAPI(session: session))
        await store.refresh()
        await store.loadMore()
        XCTAssertEqual(store.messages.count, 20)
        XCTAssertNotNil(store.paginationError)
        XCTAssertFalse(store.isLoadingMore)
        StubURLProtocol.install { request in
            guard request.url!.lastPathComponent == "messages" else { return .rows([]) }
            XCTAssertEqual(request.query["offset"], "20")
            return .rows([messageRow(id: "20")])
        }
        await store.loadMore()
        XCTAssertEqual(store.messages.last?.id, "20")
        XCTAssertNil(store.paginationError)
        XCTAssertFalse(store.canLoadMore)
    }

    func testSwitchingBoardDiscardsAnOlderInFlightPage() async {
        let requestedOldPage = expectation(description: "Older page requested")
        let session = makeStubSession { request in
            guard request.url!.lastPathComponent == "messages" else { return .rows([]) }
            if request.query["board_id"] == "eq.apps" {
                return .rows([messageRow(id: "app", board: "apps")])
            }
            if request.query["offset"] == "20" {
                requestedOldPage.fulfill()
                return .rows([messageRow(id: "stale")], delay: 0.2)
            }
            return .rows((0..<20).map { messageRow(id: String($0)) })
        }
        defer { session.invalidateAndCancel() }
        let store = FeedStore(api: MessageAPI(session: session))
        await store.refresh()
        let oldPage = Task { await store.loadMore() }
        await fulfillment(of: [requestedOldPage], timeout: 2)
        await store.selectBoard(Board(id: "apps", slug: "apps", name: "Apps", description: ""))
        await oldPage.value
        XCTAssertEqual(store.selectedBoardID, "apps")
        XCTAssertEqual(store.messages.map(\.id), ["app"])
        XCTAssertFalse(store.isLoadingMore)
    }
}
