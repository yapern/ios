import SwiftUI

struct ReplyComposer: View {
    let message: Message
    let onCreated: (Reply) -> Void
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saving = false
    @State private var error: String?
    @State private var discard = false
    @State private var showSignIn = false
    @FocusState private var focused: Bool

    private var valid: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf16.count <= 2000 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(message.title).font(.subheadline).foregroundStyle(FeedStyle.muted).lineLimit(3)
                    TextField("Write a reply", text: $text, axis: .vertical)
                        .lineLimit(6...16)
                        .focused($focused)
                        .accessibilityIdentifier("reply.body")
                } footer: {
                    Text("\(text.utf16.count)/2000")
                        .monospacedDigit()
                        .foregroundStyle(text.utf16.count > 2000 ? .red : FeedStyle.muted)
                }
                if let error { Section { InlineError(message: error) } }
                if !account.isSignedIn { Section { Button("Sign in to reply") { showSignIn = true } } }
            }
            .disabled(saving)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(FeedStyle.background)
            .navigationTitle("Reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if text.isEmpty { dismiss() } else { discard = true } }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Posting…" : "Post reply") { Task { await post() } }
                        .fontWeight(.semibold)
                        .disabled(!valid || saving || !account.isSignedIn)
                        .accessibilityIdentifier("reply.post")
                }
            }
            .interactiveDismissDisabled(saving || !text.isEmpty)
            .confirmationDialog("Discard this reply?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard reply", role: .destructive) { dismiss() }
            }
            .sheet(isPresented: $showSignIn) { SignInView() }
            .task { focused = true }
        }
    }

    private func post() async {
        guard !saving else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            let reply = try await account.authenticated {
                try await account.api.createReply(messageID: message.id, body: text, current: $0)
            }
            onCreated(reply)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
