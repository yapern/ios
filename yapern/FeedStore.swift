import Foundation
import Observation

@MainActor @Observable
final class FeedStore {
    private(set) var messages: [Message] = []
    private(set) var boards: [Board] = []
    private(set) var boardsError: String?
    private(set) var isLoadingBoards = false
    private(set) var hasLoadedBoards = false
    private(set) var isRefreshing = false
    private(set) var isLoadingMore = false
    private(set) var hasLoaded = false
    private(set) var canLoadMore = true
    private(set) var errorMessage: String?
    private(set) var paginationError: String?
    private(set) var selectedBoardID: String?

    private var authorNames: [String: String] = [:]
    private var nextOffset = 0
    private var requestVersion = 0
    let api: MessageAPI

    init(api: MessageAPI = MessageAPI()) {
        self.api = api
    }

    func loadIfNeeded() async {
        guard !hasLoaded, !isRefreshing else { return }
        await refresh()
    }

    func selectBoard(_ board: Board?) async {
        guard selectedBoardID != board?.id else { return }
        selectedBoardID = board?.id
        messages = []
        hasLoaded = false
        canLoadMore = true
        await refresh()
    }

    func refresh() async {
        requestVersion += 1
        let version = requestVersion
        isRefreshing = true
        isLoadingMore = false
        errorMessage = nil
        paginationError = nil
        defer {
            if version == requestVersion { isRefreshing = false }
        }

        // Metadata failures must not prevent people from reading messages.
        async let fetchedBoards: Void = loadBoards()
        do {
            let page = try await api.fetchMessages(offset: 0, boardID: selectedBoardID)
            try Task.checkCancellation()
            guard version == requestVersion else { return }
            messages = uniqueMessages(page)
            nextOffset = page.count
            canLoadMore = page.count == MessageAPI.pageSize
            hasLoaded = true
            await fetchedBoards
            guard version == requestVersion else { return }
            // Refresh author names too, so web account name changes appear here.
            await loadAuthors(Set(page.map(\.userID)), forceRefresh: true)
        } catch {
            guard version == requestVersion, !Task.isCancelled else { return }
            errorMessage = Self.readableError(error)
            hasLoaded = true
        }
    }

    func loadMore() async {
        guard hasLoaded, canLoadMore, !isRefreshing, !isLoadingMore, errorMessage == nil else { return }
        let version = requestVersion
        isLoadingMore = true
        paginationError = nil
        defer {
            if version == requestVersion { isLoadingMore = false }
        }
        do {
            let page = try await api.fetchMessages(offset: nextOffset, boardID: selectedBoardID)
            try Task.checkCancellation()
            guard version == requestVersion else { return }
            // New posts may shift offset pages between requests. Keep row IDs unique.
            messages = uniqueMessages(messages + page)
            nextOffset += page.count
            canLoadMore = page.count == MessageAPI.pageSize
            await loadAuthors(Set(page.map(\.userID)))
        } catch {
            guard version == requestVersion, !Task.isCancelled else { return }
            paginationError = Self.readableError(error)
        }
    }

    func loadBoards() async {
        guard !isLoadingBoards else { return }
        isLoadingBoards = true
        boardsError = nil
        defer { isLoadingBoards = false }
        do {
            let result = try await api.fetchBoards()
            try Task.checkCancellation()
            boards = result
            hasLoadedBoards = true
        } catch {
            if !Task.isCancelled { boardsError = Self.readableError(error) }
        }
    }

    func setAuthorName(_ name: String, for id: String?) {
        if let id, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { authorNames[id] = name }
    }

    func removeMessage(_ message: Message) {
        requestVersion += 1
        isLoadingMore = false
        isRefreshing = false
        if messages.contains(where: { $0.id == message.id }) {
            messages.removeAll { $0.id == message.id }
            nextOffset = max(0, nextOffset - 1)
        }
    }

    func board(for message: Message) -> Board? {
        boards.first { $0.id == message.boardID }
    }

    func authorName(for userID: String) -> String {
        authorNames[userID] ?? "Name unavailable"
    }

    func messageURL(for message: Message) -> URL? {
        guard let board = board(for: message) else { return nil }
        return URL(string: "https://yapern.com")?
            .appending(path: "y").appending(path: board.slug).appending(path: message.id)
    }

    func loadReplies(for messageID: String) async throws -> [Reply] {
        do {
            let replies = try await api.fetchReplies(messageID: messageID)
            await loadAuthors(Set(replies.map(\.userID)))
            try Task.checkCancellation()
            return replies
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw FeedError(message: Self.readableError(error))
        }
    }

    private func loadAuthors(_ ids: Set<String>, forceRefresh: Bool = false) async {
        let missingIDs = ids.filter { forceRefresh || authorNames[$0] == nil }
        await withTaskGroup(of: (String, String?).self) { group in
            for id in missingIDs {
                group.addTask { [api] in
                    (id, try? await api.fetchAuthor(id: id))
                }
            }
            for await (id, name) in group {
                guard !Task.isCancelled else { continue }
                if let name { authorNames[id] = name }
            }
        }
    }

    private func uniqueMessages(_ values: [Message]) -> [Message] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private static func readableError(_ error: Error) -> String {
        if let error = error as? MessageAPIError { return error.localizedDescription }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You’re offline. Check your connection and try again."
            case .timedOut:
                return "Loading took too long. Please try again."
            default: break
            }
        }
        return "Couldn’t load messages. Please try again."
    }
}

private struct FeedError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
