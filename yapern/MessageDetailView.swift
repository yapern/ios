import SwiftUI

struct MessageDetailView: View {
    let message: Message
    let store: FeedStore
    @Environment(AccountStore.self) private var account
    @Environment(FeedStore.self) private var mainFeed
    @Environment(\.dismiss) private var dismiss
    @State private var showReply = false
    @State private var showSignIn = false
    @State private var replyAfterSignIn = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteError: String?

    @State private var replies: [Reply] = []
    @State private var isLoadingReplies = true
    @State private var repliesError: String?

    private var boardName: String {
        store.board(for: message)?.name ?? "Yapern"
    }

    private var authorName: String {
        let name = store.authorName(for: message.userID)
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Someone" : name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Text(boardName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FeedStyle.accent)
                            .lineLimit(1)
                        Text("·")
                            .foregroundStyle(FeedStyle.muted)
                        Text(authorName)
                            .font(.subheadline)
                            .foregroundStyle(FeedStyle.muted)
                            .lineLimit(1)
                    }

                    Text(message.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled message" : message.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(FeedStyle.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(message.createdAt.formatted(date: .long, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(FeedStyle.muted)

                    MessageBodyView(messageBody: message.body)
                        .padding(.top, 2)
                }
                .padding(16)

                FeedStyle.divider
                    .frame(height: 1)
                    .padding(.horizontal, 16)

                repliesSection
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                    .accessibilityIdentifier("detail.replies")
            }
            .frame(maxWidth: FeedStyle.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .background(FeedStyle.background)
        .navigationTitle("Message")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = store.messageURL(for: message) {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("detail.share")
                    .accessibilityLabel("Share message")
                }
            }
            if account.userID == message.userID {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Delete message", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(deleting)
                    .accessibilityLabel("Message actions")
                    .accessibilityIdentifier("detail.actions")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    if account.isSignedIn { showReply = true }
                    else { replyAfterSignIn = true; showSignIn = true }
                } label: {
                    Label("Reply to this message", systemImage: "arrowshape.turn.up.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("detail.reply")
                .disabled(deleting)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .refreshable { await fetchReplies() }
        .sheet(isPresented: $showReply) {
            ReplyComposer(message: message) { reply in
                replies.removeAll { $0.id == reply.id }
                replies.append(reply)
                store.setAuthorName(account.profileName, for: account.userID)
            }
        }
        .sheet(isPresented: $showSignIn, onDismiss: {
            if replyAfterSignIn && account.isSignedIn { showReply = true }
            replyAfterSignIn = false
        }) { SignInView() }
        .confirmationDialog("Delete this message?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete message", role: .destructive) { Task { await deleteMessage() } }
        } message: { Text("This also deletes its replies. This cannot be undone.") }
        .alert("Couldn’t delete message", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: { Text(deleteError ?? "") }
        .overlay { if deleting { ProgressView("Deleting…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .task(id: message.id) { await fetchReplies() }
        .tint(FeedStyle.accent)
    }

    @ViewBuilder
    private var repliesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Replies")
                .font(.headline)
                .foregroundStyle(FeedStyle.text)
                .accessibilityAddTraits(.isHeader)

            if isLoadingReplies {
                ProgressView()
                    .tint(FeedStyle.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .accessibilityLabel("Loading replies")
            } else if let repliesError {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn’t load replies")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FeedStyle.text)
                    Text(repliesError)
                        .font(.subheadline)
                        .foregroundStyle(FeedStyle.muted)
                    Button("Try again") { Task { await fetchReplies() } }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .disabled(isLoadingReplies)
                }
            } else if replies.isEmpty {
                Text("No replies yet.")
                    .font(.subheadline)
                    .foregroundStyle(FeedStyle.muted)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(replies.enumerated()), id: \.element.id) { index, reply in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(replyAuthorName(for: reply))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(FeedStyle.text)
                                Spacer(minLength: 8)
                                Text(reply.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(FeedStyle.muted)
                            }
                            MessageBodyView(messageBody: reply.body)
                        }
                        .padding(.vertical, 14)

                        if index < replies.count - 1 {
                            FeedStyle.divider.frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func replyAuthorName(for reply: Reply) -> String {
        let name = store.authorName(for: reply.userID)
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Someone" : name
    }

    @MainActor
    private func fetchReplies() async {
        isLoadingReplies = true
        repliesError = nil
        defer { isLoadingReplies = false }
        do {
            let loaded = try await store.loadReplies(for: message.id)
            var byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            for reply in replies { byID[reply.id] = reply }
            replies = byID.values.sorted { $0.createdAt < $1.createdAt }
        } catch is CancellationError {
            return
        } catch {
            repliesError = error.localizedDescription
        }
    }
    @MainActor
    private func deleteMessage() async {
        guard !deleting else { return }
        deleting = true
        defer { deleting = false }
        do {
            try await account.authenticated { try await account.api.deleteMessage(message, current: $0) }
            store.removeMessage(message)
            if store !== mainFeed { mainFeed.removeMessage(message) }
            dismiss()
        } catch { deleteError = error.localizedDescription }
    }

}
