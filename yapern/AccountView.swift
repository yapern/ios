import SwiftUI

struct AccountView: View {
    @Environment(AccountStore.self) private var account
    @Environment(FeedStore.self) private var feed
    @State private var name = ""
    @State private var error: String?
    @State private var feedback: String?
    @State private var loading = false
    @State private var saving = false
    @State private var profileLoaded = false
    @State private var showSignIn = false
    @State private var showSignOut = false
    @State private var page: WebPage?

    var body: some View {
        NavigationStack {
            Form {
                if account.isSignedIn {
                    Section {
                        LabeledContent("Email", value: account.session?.user.email ?? "")
                            .textSelection(.enabled)
                        LabeledContent("Display name") {
                            TextField("Name", text: $name)
                                .textContentType(.name)
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("account.name")
                                .disabled(loading || saving || !profileLoaded)
                        }
                        if loading { ProgressView("Loading profile…") }
                        Button(saving ? "Saving…" : "Save name") { Task { await saveName() } }
                            .accessibilityIdentifier("account.save")
                            .disabled(loading || saving || !profileLoaded || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.utf16.count > 80 || name == account.profileName)
                        if let feedback { Text(feedback).foregroundStyle(FeedStyle.muted).font(.subheadline) }
                    } header: { Text("Profile") }
                    if let error {
                        Section {
                            InlineError(message: error)
                            if !profileLoaded { Button("Try again") { Task { await loadProfile() } }.disabled(loading) }
                        }
                    }
                    Section {
                        Button("Sign out", role: .destructive) { showSignOut = true }
                            .disabled(account.isBusy || saving)
                            .accessibilityIdentifier("account.signout")
                    }
                } else {
                    Section {
                        Text("Sign in to post messages, reply, and create sub-yaps.")
                            .foregroundStyle(FeedStyle.muted)
                        Button("Sign in or create account") { showSignIn = true }
                            .accessibilityIdentifier("account.signin")
                        if let sessionError = account.sessionError { InlineError(message: sessionError) }
                    }
                }
                Section("Yapern") {
                    Button { page = WebPage(path: "blog/") } label: { Label("Blog", systemImage: "doc.text") }
                    Button { page = WebPage(path: "privacy/") } label: { Label("Privacy policy", systemImage: "hand.raised") }
                    Button { page = WebPage(path: "terms/") } label: { Label("Terms of service", systemImage: "doc.plaintext") }
                    ShareLink(item: URL(string: "https://yapern.com")!) { Label("Share Yapern", systemImage: "square.and.arrow.up") }
                }
            }
            .scrollContentBackground(.hidden)
            .background(FeedStyle.background)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: account.userID) {
                error = nil
                feedback = nil
                profileLoaded = false
                if account.isSignedIn { await loadProfile() }
            }
            .refreshable {
                await account.validateSession()
                if account.isSignedIn { await loadProfile() }
            }
            .sheet(isPresented: $showSignIn) { SignInView() }
            .sheet(item: $page) { SafariView(url: $0.url).ignoresSafeArea() }
            .confirmationDialog("Sign out of Yapern?", isPresented: $showSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task {
                        do { try await account.signOut() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }

    private func loadProfile() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            try await account.loadProfile()
            name = account.profileName
            profileLoaded = true
        } catch { self.error = error.localizedDescription }
    }

    private func saveName() async {
        saving = true
        error = nil
        feedback = nil
        defer { saving = false }
        do {
            try await account.saveName(name)
            name = account.profileName
            feed.setAuthorName(name, for: account.userID)
            feedback = "Name saved."
        } catch { self.error = error.localizedDescription }
    }
}

struct SignInView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @FocusState private var focusedField: Field?
    private enum Field { case email, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email").font(.subheadline).foregroundStyle(FeedStyle.muted)
                        TextField("name@example.com", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                            .accessibilityIdentifier("signin.email")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password").font(.subheadline).foregroundStyle(FeedStyle.muted)
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { if canSubmit { Task { await signIn() } } }
                            .accessibilityIdentifier("signin.password")
                    }
                } footer: {
                    Text("New here? We’ll create your account. Use at least 8 characters for a new password.")
                }
                .disabled(account.isBusy)
                if let error { Section { InlineError(message: error) } }
                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            Text(account.isBusy ? "Signing in…" : "Continue with email")
                            Spacer()
                            if account.isBusy { ProgressView() }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(FeedStyle.background)
                    .listRowBackground(Color.clear)
                    .disabled(!canSubmit || account.isBusy)
                    .accessibilityIdentifier("signin.submit")
                }
            }
            .scrollContentBackground(.hidden)
            .background(FeedStyle.background)
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(account.isBusy) } }
            .interactiveDismissDisabled(account.isBusy)
        }
    }

    private var canSubmit: Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).contains("@") && email.utf16.count <= 254 &&
            !password.isEmpty && password.utf16.count <= 128
    }

    private func signIn() async {
        error = nil
        do {
            try await account.signIn(email: email, password: password)
            password = ""
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct InlineError: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.subheadline)
            .foregroundStyle(FeedStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("inline.error")
    }
}
