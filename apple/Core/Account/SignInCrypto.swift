import CryptoKit
import Foundation

/// The nonce every sign-in carries (docs/WORKER.md "The nonce"). The raw value
/// goes to the Worker; Apple's request carries its SHA-256 in hex, which is
/// what Apple puts in the identity token. Google's request carries it raw.
nonisolated enum SignInNonce {
    static func make() -> String { randomURLSafe(bytes: 32) }

    static func sha256Hex(_ raw: String) -> String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// RFC 7636 proof key for an installed app, which can keep no client secret.
nonisolated enum PKCE {
    static func verifier() -> String { randomURLSafe(bytes: 32) }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
}

/// Google's authorization-code flow with PKCE, for the system web
/// authentication session. No SDK: the request is a URL and the answer a
/// redirect to the reversed client id, the scheme Google gives an iOS client.
nonisolated struct GoogleAuthRequest: Sendable {
    let clientID: String
    let verifier: String
    let state: String
    let nonce: String

    init(clientID: String, verifier: String = PKCE.verifier(), state: String = randomURLSafe(bytes: 16),
         nonce: String = SignInNonce.make()) {
        self.clientID = clientID
        self.verifier = verifier
        self.state = state
        self.nonce = nonce
    }

    /// `123-abc.apps.googleusercontent.com` -> `com.googleusercontent.apps.123-abc`
    var callbackScheme: String {
        "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }

    var redirectURI: String { callbackScheme + ":/oauth2redirect" }

    var url: URL {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid"),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
        ]
        return c.url!
    }

    /// The code from the redirect, or nil when the state does not match.
    func code(from callback: URL) -> String? {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { return nil }
        return items.first(where: { $0.name == "code" })?.value
    }
}

nonisolated func randomURLSafe(bytes count: Int) -> String {
    var bytes = [UInt8](repeating: 0, count: count)
    for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
    return base64URL(Data(bytes))
}

nonisolated func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
