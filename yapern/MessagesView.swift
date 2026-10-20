import SwiftUI

struct MessagesView: View {
    let store: FeedStore
    var board: Board? = nil
    @Environment(AccountStore.self) private var account
    @State private var showComposer = false
    @State private var showSignIn = false
    @State private var composeAfterSignIn = false
    @State private var createdMessage: Message?

    private struct PaginationTaskID: Hashable {
        let lastMessageID: String?
        let isRefreshing: Bool
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                feedHeader

                if store.messages.isEmpty {
                    emptyOrLoadingState
                } else {
                    if let error = store.errorMessage {
                        refreshError(error)
                    }
                    ForEach(store.messages) { message in
                        MessageRow(message: message, store: store)
                        if message.id != store.messages.last?.id {
                            FeedStyle.divider
                                .frame(height: 1)
                                .padding(.leading, 16)
                        }
                    }

                    paginationFooter
                }
            }
            .frame(maxWidth: FeedStyle.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("feed.scroll")
        .background(FeedStyle.background)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refresh() }
        .task {
            if let board { await store.selectBoard(board) }
            else { await store.loadIfNeeded() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if account.isSignedIn { showComposer = true }
                    else { composeAfterSignIn = true; showSignIn = true }
                } label: { Image(systemName: "square.and.pencil").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("New message")
                .accessibilityIdentifier("feed.compose")
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                    Text(board?.name ?? "Yapern")
                        .font(.headline)
                        .foregroundStyle(FeedStyle.text)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .toolbarBackground(FeedStyle.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(item: $createdMessage) { message in
            MessageDetailView(message: message, store: store)
        }
        .sheet(isPresented: $showComposer, onDismiss: {
            Task { await store.refresh() }
        }) {
            MessageComposer(store: store) { message in
                createdMessage = message
            }
        }
        .sheet(isPresented: $showSignIn, onDismiss: {
            if composeAfterSignIn && account.isSignedIn { showComposer = true }
            composeAfterSignIn = false
        }) { SignInView() }
        .onChange(of: account.profileName) { _, name in store.setAuthorName(name, for: account.userID) }
        .tint(FeedStyle.accent)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var feedHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                heading
                Spacer(minLength: 0)
                if board == nil { boardFilter }
            }
            VStack(alignment: .leading, spacing: 2) {
                heading
                if board == nil { boardFilter }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 8)
        if let board, !board.description.isEmpty {
            Text(board.description)
                .font(.subheadline)
                .foregroundStyle(FeedStyle.muted)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    private var heading: some View {
        Text(board == nil ? "Latest messages" : "Messages")
            .font(.title3.weight(.semibold))
            .foregroundStyle(FeedStyle.text)
            .accessibilityAddTraits(.isHeader)
    }

    private var boardFilter: some View {
        Menu {
            Button {
                Task { await store.selectBoard(nil) }
            } label: {
                if store.selectedBoardID == nil {
                    Label("All sub-yaps", systemImage: "checkmark")
                } else {
                    Text("All sub-yaps")
                }
            }

            if !store.boards.isEmpty {
                Divider()
                ForEach(store.boards) { board in
                    Button {
                        Task { await store.selectBoard(board) }
                    } label: {
                        if store.selectedBoardID == board.id {
                            Label(board.name, systemImage: "checkmark")
                        } else {
                            Text(board.name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selectedBoardName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(FeedStyle.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("feed.filter")
        .accessibilityLabel("Filter messages. Current filter: \(selectedBoardName)")
        .disabled(store.boards.isEmpty)
    }

    private var selectedBoardName: String {
        guard let selectedBoardID = store.selectedBoardID else { return "All sub-yaps" }
        return store.boards.first(where: { $0.id == selectedBoardID })?.name ?? "All sub-yaps"
    }

    private func refreshError(_ error: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(error)
                .font(.subheadline)
                .foregroundStyle(FeedStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Retry") { Task { await store.refresh() } }
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var emptyOrLoadingState: some View {
        if store.isRefreshing || !store.hasLoaded {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 4).fill(FeedStyle.skeleton).frame(width: 150, height: 13)
                        RoundedRectangle(cornerRadius: 4).fill(FeedStyle.skeleton).frame(height: 18)
                        RoundedRectangle(cornerRadius: 4).fill(FeedStyle.skeleton).frame(width: 220, height: 18)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 28)
            .accessibilityLabel("Loading latest messages")
        } else if let error = store.errorMessage {
            VStack(alignment: .leading, spacing: 10) {
                Text("Couldn’t load messages")
                    .font(.headline)
                    .foregroundStyle(FeedStyle.text)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(FeedStyle.muted)
                Button("Try again") { Task { await store.refresh() } }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        } else {
            Text("No messages yet.")
                .font(.body)
                .foregroundStyle(FeedStyle.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }

    private var paginationFooter: some View {
        Group {
            if store.isLoadingMore {
                ProgressView()
                    .tint(FeedStyle.accent)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .accessibilityLabel("Loading older messages")
            } else if let error = store.paginationError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(FeedStyle.muted)
                    Button("Try loading older messages again") { Task { await store.loadMore() } }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .padding(16)
            } else if store.canLoadMore {
                Color.clear.frame(height: 1)
            }
        }
        .task(id: PaginationTaskID(lastMessageID: store.messages.last?.id, isRefreshing: store.isRefreshing)) {
            guard store.canLoadMore, !store.isRefreshing, store.paginationError == nil else { return }
            await store.loadMore()
        }
    }
}
