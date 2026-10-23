import AuthenticationServices
#if os(iOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Asks Sign in with Apple once more, outside a button: Delete Account needs a
/// FRESH authorization code for the Worker to revoke the Apple token
/// (Decision 063; App Review 5.1.1(v)). Sign-in itself uses the system's
/// `SignInWithAppleButton`.
final class AppleAuthorization: NSObject {
    nonisolated struct Result: Sendable {
        let user: String
        let identityToken: String?
        let authorizationCode: String?
    }

    private var continuation: CheckedContinuation<Result, Error>?
    private var controller: ASAuthorizationController?

    func request(nonceHash: String? = nil) async throws -> Result {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        request.nonce = nonceHash
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    static func result(from authorization: ASAuthorization) -> Result? {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return nil }
        return Result(user: credential.user,
                      identityToken: credential.identityToken.map { String(decoding: $0, as: UTF8.self) },
                      authorizationCode: credential.authorizationCode.map { String(decoding: $0, as: UTF8.self) })
    }

    private func finish(_ result: Swift.Result<Result, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }

    static func isCanceled(_ error: Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }
}

extension AppleAuthorization: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        if let result = Self.result(from: authorization) {
            finish(.success(result))
        } else {
            finish(.failure(ASAuthorizationError(.invalidResponse)))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish(.failure(error))
    }
}

extension AppleAuthorization: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(iOS) || os(tvOS)
        // Asked only from a button on screen, so a window scene is connected.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? UIWindow(windowScene: scenes[0])
        #elseif os(macOS)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #endif
    }
}
