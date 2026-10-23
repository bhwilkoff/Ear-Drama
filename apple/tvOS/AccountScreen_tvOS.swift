#if os(tvOS)
import AuthenticationServices
import SwiftUI

/// The account at ten feet (tvOS-DESIGN §4.9): Sign in with Apple only, since
/// `ASWebAuthenticationSession` does not exist on tvOS and the TV's Google
/// path (a phone hand-off) waits on its own rule.
struct AccountScreen_tvOS: View {
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
                    AppleSignInButton()
                        .signInWithAppleButtonStyle(.white)
                        .frame(width: 560, height: 90)
                    if let error = account.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.semanticError)
                    }
                }
                .disabled(account.isWorking)
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
#endif
