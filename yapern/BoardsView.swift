import SwiftUI

struct BoardsView: View {
    @Environment(FeedStore.self) private var store
    @Environment(AccountStore.self) private var account
    @State private var search = ""
    @State private var searchPresented = false
    @State private var showComposer = false
    @State private var showSignIn = false
    @State private var createAfterSignIn = false
    @State private var createdBoard: Board?

    private var filteredBoards: [Board] {
        guard !search.isEmpty else { return store.boards }
        return store.boards.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.slug.localizedCaseInsensitiveContains(search) ||
                $0.description.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.isLoadingBoards && store.boards.isEmpty {
                    ProgressView("Loading sub-yaps…").listRowBackground(Color.clear)
                }
                if let error = store.boardsError {
                    InlineError(message: error)
                    Button("Try again") { Task { await store.loadBoards() } }.disabled(store.isLoadingBoards)
                }
                if filteredBoards.isEmpty && !store.isLoadingBoards && store.boardsError == nil {
                    Text(search.isEmpty ? "No sub-yaps yet." : "No sub-yaps match your search.")
                        .foregroundStyle(FeedStyle.muted)
                        .listRowBackground(Color.clear)
                }
                ForEach(filteredBoards) { board in
                    NavigationLink(value: board) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(board.name).font(.headline).foregroundStyle(FeedStyle.text)
                            Text("y/\(board.slug)").font(.subheadline).foregroundStyle(FeedStyle.accent)
                            if !board.description.isEmpty {
                                Text(board.description).font(.subheadline).foregroundStyle(FeedStyle.muted).lineLimit(3)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .accessibilityIdentifier("boards.\(board.slug)")
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(FeedStyle.background)
            .navigationTitle("Sub-yaps")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, isPresented: $searchPresented, prompt: "Find a sub-yap")
            .onSubmit(of: .search) { searchPresented = false }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if account.isSignedIn { showComposer = true }
                        else { createAfterSignIn = true; showSignIn = true }
                    } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Create sub-yap")
                    .accessibilityIdentifier("boards.create")
                }
            }
            .navigationDestination(for: MessageRoute.self) { route in
                MessageDetailView(message: route.message, store: route.store)
            }
            .navigationDestination(for: Board.self) { board in BoardMessagesView(board: board) }
            .navigationDestination(item: $createdBoard) { board in BoardMessagesView(board: board) }
            .refreshable { await store.loadBoards() }
            .task { if !store.hasLoadedBoards { await store.loadBoards() } }
            .sheet(isPresented: $showComposer, onDismiss: { Task { await store.loadBoards() } }) {
                BoardComposer { createdBoard = $0 }
            }
            .sheet(isPresented: $showSignIn, onDismiss: {
                if createAfterSignIn && account.isSignedIn { showComposer = true }
                createAfterSignIn = false
            }) { SignInView() }
        }
    }
}

struct BoardMessagesView: View {
    let board: Board
    @Environment(AccountStore.self) private var account
    @State private var store: FeedStore?
    var body: some View {
        Group {
            if let store { MessagesView(store: store, board: board) }
            else { ProgressView().task { store = FeedStore(api: account.api) } }
        }
    }
}
