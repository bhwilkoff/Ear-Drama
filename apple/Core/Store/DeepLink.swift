import Foundation

/// What an opened URL asks for (DEEP_LINKS.md). `onOpenURL` and the Universal
/// Link continuation post the answer to the inbox and never route themselves.
nonisolated enum DeepLink {
    /// Every `eardrama://` link and its `https://eardrama.org` twin share a path:
    /// `series/{key}`, `episode/{id}`, `person/{id}`, `drama/{pid}`, `search?q=`, `library`,
    /// `invite#{token}`. Anything else (another host, the OAuth callback, an
    /// unknown path) opens nothing, so the app stays where it was.
    static func parse(_ url: URL) -> AppStore.InboxRequest? {
        if let token = inviteToken(url) { return .invite(token) }
        guard let segments = segments(url), let head = segments.first else { return nil }
        let value = segments.count > 1 && !segments[1].isEmpty ? segments[1] : nil
        switch head {
        case "series": return value.map { .series($0) }
        case "episode": return value.map { .episode($0) }
        case "person": return value.map { .person($0) }
        case "drama": return value.map { .drama($0) }
        case "search":
            // `+` is a space, as the web's URLSearchParams reads it.
            let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .percentEncodedQueryItems?.first(where: { $0.name == "q" })?.value ?? ""
            let q = raw.replacingOccurrences(of: "+", with: " ")
            return .search(q.removingPercentEncoding ?? q)
        case "library": return .tab("library")
        default: return nil
        }
    }

    /// The decoded path segments, the custom scheme's host first. Nil for a
    /// link that is not ours.
    private static func segments(_ url: URL) -> [String]? {
        let path = url.path(percentEncoded: true).split(separator: "/").map(String.init)
        let raw: [String]
        if url.scheme?.lowercased() == "eardrama" {
            raw = (url.host(percentEncoded: true).map { [$0] } ?? []) + path
        } else if isOurs(url) {
            raw = path
        } else {
            return nil
        }
        return raw.map { $0.removingPercentEncoding ?? $0 }
    }

    /// 32 random bytes as base64url: 43 characters.
    static func isToken(_ s: String) -> Bool {
        s.utf8.count == 43 && s.utf8.allSatisfy { b in
            (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x2D || b == 0x5F
        }
    }

    /// The token from `…/invite#{token}`, or from the `#invite={token}` the
    /// web's 404 forwarder leaves.
    static func inviteToken(_ url: URL) -> String? {
        guard url.scheme == "eardrama" || isOurs(url) else { return nil }
        let hash = url.fragment ?? ""
        if let named = URLComponents(string: "x:?\(hash)")?.queryItems?.first(where: { $0.name == "invite" })?.value,
           isToken(named) { return named }
        return isInvitePath(url) && isToken(hash) ? hash : nil
    }

    private static func isOurs(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return url.scheme == "https" && (host == "eardrama.org" || host.hasSuffix(".eardrama.org"))
    }

    private static func isInvitePath(_ url: URL) -> Bool {
        if url.scheme == "eardrama" { return url.host == "invite" }
        return isOurs(url) && (url.path == "/invite" || url.path == "/invite/")
    }
}
