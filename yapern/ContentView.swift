import SwiftUI

struct ContentView: View {
    @State private var account: AccountStore
    @State private var feed: FeedStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let api = UITestURLProtocol.makeAPI()
            _account = State(initialValue: AccountStore(api: api, storage: UITestSessionStorage(signedIn: ProcessInfo.processInfo.arguments.contains("--ui-signed-in"))))
            _feed = State(initialValue: FeedStore(api: api))
            return
        }
        #endif
        _account = State(initialValue: AccountStore())
        _feed = State(initialValue: FeedStore())
    }

    var body: some View {
        TabView {
            Tab("Messages", systemImage: "bubble.left.and.bubble.right") {
                NavigationStack {
                    MessagesView(store: feed)
                        .navigationDestination(for: MessageRoute.self) { route in
                            MessageDetailView(message: route.message, store: route.store)
                        }
                        .navigationDestination(for: Board.self) { BoardMessagesView(board: $0) }
                }
            }
            Tab("Sub-yaps", systemImage: "number") {
                BoardsView()
            }
            Tab("Account", systemImage: "person.crop.circle") {
                AccountView()
            }
        }
        .environment(account)
        .environment(feed)
        .tint(FeedStyle.accent)
        .preferredColorScheme(.dark)
        .task { await account.validateSession() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await account.validateSession() } }
        }
        .onChange(of: account.profileName) { _, name in
            if !name.isEmpty { feed.setAuthorName(name, for: account.userID) }
        }
    }
}
