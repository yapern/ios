import SwiftUI

struct MessageComposer: View {
    let store: FeedStore
    let onCreated: (Message) -> Void
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var boardID = ""
    @State private var title = ""
    @State private var text = ""
    @State private var link = ""
    @State private var hasLink = false
    @State private var previewImage: URL?
    @State private var previewSource = ""
    @State private var previewLoading = false
    @State private var previewError: String?
    @State private var error: String?
    @State private var saving = false
    @State private var discard = false
    @State private var showSignIn = false

    private var serializedBody: String {
        MessageDraft.body(text: text, link: hasLink ? link : "", image: hasLink && previewSource == link ? previewImage : nil)
    }
    private var hasChanges: Bool { !title.isEmpty || !text.isEmpty || !link.isEmpty }
    private var canPost: Bool {
        store.boards.contains { $0.id == boardID } && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            title.utf16.count <= 200 && !serializedBody.isEmpty && serializedBody.utf16.count <= 2000 &&
            (!hasLink || MessageDraft.webURL(link) != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.isLoadingBoards && store.boards.isEmpty {
                        ProgressView("Loading sub-yaps…")
                    } else if !store.boards.isEmpty {
                        Picker("Post to", selection: $boardID) {
                            Text("Choose a sub-yap").tag("")
                            ForEach(store.boards) { Text("y/\($0.slug)").tag($0.id) }
                        }
                        .accessibilityIdentifier("compose.board")
                        if let board = store.boards.first(where: { $0.id == boardID }), !board.description.isEmpty {
                            Text(board.description).font(.subheadline).foregroundStyle(FeedStyle.muted)
                        }
                    } else {
                        Text("No sub-yaps available.")
                    }
                    if let boardsError = store.boardsError {
                        InlineError(message: boardsError)
                        Button("Retry loading sub-yaps") { Task { await store.loadBoards() } }
                    }
                }
                Section("Title") {
                    TextField("Give your message a title", text: $title, axis: .vertical)
                        .accessibilityIdentifier("compose.title")
                    if title.utf16.count > 200 { InlineError(message: "Keep the title within 200 characters.") }
                }
                Section {
                    TextField("Write a message", text: $text, axis: .vertical)
                        .lineLimit(6...16)
                        .accessibilityIdentifier("compose.body")
                } header: {
                    Text(hasLink ? "Message (optional)" : "Message")
                } footer: {
                    Text("\(serializedBody.utf16.count)/2000")
                        .foregroundStyle(serializedBody.utf16.count > 2000 ? .red : FeedStyle.muted)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Section {
                    if hasLink {
                        TextField("https://example.com", text: $link)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Link URL")
                            .accessibilityIdentifier("compose.link")
                        if !link.isEmpty && MessageDraft.webURL(link) == nil { InlineError(message: "Enter a full http or https URL.") }
                        if previewLoading { ProgressView("Loading preview…") }
                        if let previewImage, previewSource == link {
                            AsyncImage(url: previewImage) { image in
                                image.resizable().scaledToFit().frame(maxHeight: 180)
                            } placeholder: { Image(systemName: "link").foregroundStyle(FeedStyle.muted) }
                            .accessibilityLabel("Link preview")
                        }
                        if let previewError { Text(previewError).font(.footnote).foregroundStyle(FeedStyle.muted) }
                        Button("Remove link", role: .destructive) {
                            hasLink = false
                            link = ""
                            previewImage = nil
                        }
                    } else {
                        Button { hasLink = true } label: { Label("Add a link", systemImage: "link") }
                            .accessibilityIdentifier("compose.addlink")
                    }
                }
                if let error { Section { InlineError(message: error) } }
                if !account.isSignedIn {
                    Section { Button("Sign in to post") { showSignIn = true } }
                }
            }
            .disabled(saving)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(FeedStyle.background)
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if hasChanges { discard = true } else { dismiss() } }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Posting…" : "Post") { Task { await post() } }
                        .fontWeight(.semibold)
                        .disabled(!canPost || saving || !account.isSignedIn)
                        .accessibilityIdentifier("compose.post")
                }
            }
            .interactiveDismissDisabled(saving || hasChanges)
            .confirmationDialog("Discard this message?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard message", role: .destructive) { dismiss() }
            }
            .sheet(isPresented: $showSignIn) { SignInView() }
            .task {
                if store.boards.isEmpty { await store.loadBoards() }
                if boardID.isEmpty { boardID = store.selectedBoardID ?? "" }
            }
            .task(id: hasLink ? link : "") { await loadPreview() }
        }
    }

    private func loadPreview() async {
        previewImage = nil
        previewError = nil
        previewLoading = false
        guard hasLink, let url = MessageDraft.webURL(link), account.isSignedIn else { return }
        let source = link
        do {
            try await Task.sleep(for: .milliseconds(500))
            guard !saving else { return }
            previewLoading = true
            let image = try await account.authenticated { try await account.api.fetchPreview(url: url, current: $0) }
            try Task.checkCancellation()
            guard source == link else { return }
            previewSource = source
            previewImage = image
            previewLoading = false
            if image == nil { previewError = "No preview available. Your link will still be included." }
        } catch {
            guard !Task.isCancelled, source == link else { return }
            previewLoading = false
            previewError = "Preview unavailable. Your link will still be included."
        }
    }

    private func post() async {
        guard canPost, !saving else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            // Use a completed preview only; a slow preview never blocks posting.
            let message = try await account.authenticated {
                try await account.api.createMessage(boardID: boardID, title: title, body: serializedBody, current: $0)
            }
            onCreated(message)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct BoardComposer: View {
    let onCreated: (Board) -> Void
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var saving = false
    @State private var error: String?
    @State private var discard = false
    @State private var showSignIn = false

    private var slug: String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression) }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.utf16.count <= 80 && description.utf16.count <= 2000 &&
            slug.range(of: #"^[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?$"#, options: .regularExpression) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).accessibilityIdentifier("board.name")
                    if !slug.isEmpty { Text("y/\(slug)").font(.subheadline).foregroundStyle(FeedStyle.muted) }
                } header: { Text("Name") } footer: { Text("Use letters, numbers, spaces, or hyphens. Up to 80 characters.") }
                Section {
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(4...10)
                        .accessibilityIdentifier("board.description")
                } header: { Text("Description") } footer: { Text("\(description.utf16.count)/2000").monospacedDigit() }
                if let error { Section { InlineError(message: error) } }
                if !account.isSignedIn { Section { Button("Sign in to create") { showSignIn = true } } }
            }
            .disabled(saving)
            .scrollContentBackground(.hidden)
            .background(FeedStyle.background)
            .navigationTitle("New sub-yap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if name.isEmpty && description.isEmpty { dismiss() } else { discard = true } }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Creating…" : "Create") { Task { await create() } }
                        .fontWeight(.semibold)
                        .disabled(!valid || saving || !account.isSignedIn)
                        .accessibilityIdentifier("board.create")
                }
            }
            .interactiveDismissDisabled(saving || !name.isEmpty || !description.isEmpty)
            .confirmationDialog("Discard this sub-yap?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard sub-yap", role: .destructive) { dismiss() }
            }
            .sheet(isPresented: $showSignIn) { SignInView() }
        }
    }

    private func create() async {
        guard !saving else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            let board = try await account.authenticated {
                try await account.api.createBoard(name: name, description: description, current: $0)
            }
            onCreated(board)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
