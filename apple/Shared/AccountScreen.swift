import AuthenticationServices
import SwiftUI

/// Library's last row (iOS-DESIGN §4.10, macOS-DESIGN §4.4, tvOS-DESIGN §4.9):
/// "Account" and its state. Disabled, with no error, while the build carries
/// placeholder ids.
struct AccountRow: View {
    @Environment(AccountStore.self) private var account

    var body: some View {
        NavigationLink(value: Route.account) {
            LabeledContent {
                Text(summary)
            } label: {
                Label("Account", systemImage: "person.crop.circle")
            }
        }
        .disabled(account.status == .unavailable)
    }

    private var summary: String {
        switch account.status {
        case .unavailable: return "Not available"
        case .signedOut: return "Not signed in"
        case .signedIn:
            if account.lastError != nil { return "Sync failed" }
            guard let last = account.lastSync else { return "Not synced yet" }
            return "Synced " + last.formatted(date: .omitted, time: .shortened)
        }
    }
}

/// The account's state and verbs: what it is, when it last synced, the last
/// error, Sync Now, Sign Out, and Delete Account.
struct AccountStatusSection: View {
    @Environment(AccountStore.self) private var account
    let provider: AccountProvider

    var body: some View {
        Section {
            LabeledContent("Signed in with", value: provider.title)
            LabeledContent("Last sync") {
                if let last = account.lastSync {
                    Text(verbatim: last.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("Never")
                }
            }
            if let error = account.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.semanticError)
            }
            Button("Sync Now") { Task { await account.sync() } }
                .disabled(account.isWorking)
        }
    }
}

/// Apple's own button, with the nonce's hash in the request and the raw nonce
/// sent to the Worker. No name or email is asked for: the Worker keeps neither.
struct AppleSignInButton: View {
    @Environment(AccountStore.self) private var account
    @State private var nonce = SignInNonce.make()

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            nonce = SignInNonce.make()
            request.requestedScopes = []
            request.nonce = SignInNonce.sha256Hex(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let r = AppleAuthorization.result(from: authorization), let token = r.identityToken else {
                    account.report(WorkerError.badResponse)
                    return
                }
                let raw = nonce
                Task { await account.signIn(provider: .apple, idToken: token, nonce: raw, appleUserID: r.user) }
            case .failure(let error):
                if !AppleAuthorization.isCanceled(error) { account.report(error) }
            }
        }
    }
}

/// The confirmation, then (for an Apple account) a fresh authorization code,
/// then the deletion.
struct DeleteAccountModifier: ViewModifier {
    @Environment(AccountStore.self) private var account
    @Binding var isPresented: Bool
    @State private var apple = AppleAuthorization()

    func body(content: Content) -> some View {
        content.confirmationDialog("Delete Account?", isPresented: $isPresented, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your synced history, queue, and follows are deleted from the server. Listening on this device stays.")
        }
    }

    private func delete() async {
        var code: String?
        if account.provider == .apple {
            do {
                code = try await apple.request().authorizationCode
            } catch {
                if !AppleAuthorization.isCanceled(error) { account.report(error) }
                return
            }
        }
        try? await account.deleteAccount(appleAuthorizationCode: code)
    }
}

#if os(iOS) || os(macOS)
struct AccountScreen: View {
    @Environment(AccountStore.self) private var account
    @State private var confirmDelete = false

    var body: some View {
        List {
            switch account.status {
            case .unavailable:
                Text("Sign-in is not available in this build.")
                    .foregroundStyle(Color.brandTextMuted)
            case .signedOut:
                Section {
                    SignInButtons()
                }
            case .signedIn(let provider):
                AccountStatusSection(provider: provider)
                Section {
                    Button("Sign Out") { Task { await account.signOut() } }
                    Button("Delete Account", role: .destructive) { confirmDelete = true }
                }
                .disabled(account.isWorking)
            }
        }
        .navigationTitle("Account")
        .modifier(DeleteAccountModifier(isPresented: $confirmDelete))
    }
}

/// Signed out: Apple's button first, Google under it (App Review 4.8), and
/// the last error. The account screen's, and Start Recording's (PLAYS-DESIGN
/// §2.3: recording needs an account).
struct SignInButtons: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            AppleSignInButton()
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 44)
            if account.isGoogleAvailable {
                Button("Sign in with Google") { Task { await signInWithGoogle() } }
            }
            if let error = account.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.semanticError)
            }
        }
        .disabled(account.isWorking)
    }

    private func signInWithGoogle() async {
        guard let clientID = account.googleClientID else { return }
        let request = GoogleAuthRequest(clientID: clientID)
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: request.url, callback: .customScheme(request.callbackScheme),
                preferredBrowserSession: .ephemeral, additionalHeaderFields: [:])
            guard let code = request.code(from: callback) else {
                account.report(WorkerError.badResponse)
                return
            }
            await account.signInWithGoogle(code: code, request: request)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            account.report(error)
        }
    }
}
#endif
