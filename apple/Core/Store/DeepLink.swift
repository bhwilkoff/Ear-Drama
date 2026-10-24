import Foundation

/// What an opened URL asks for (DEEP_LINKS.md). `onOpenURL` posts the answer
/// to the inbox and never routes itself.
nonisolated enum DeepLink {
    /// An ear drama invite (`eardrama://invite#TOKEN`, `https://eardrama.org/invite#TOKEN`)
    /// is `.invite`; any other link names an item by its last path component.
    static func parse(_ url: URL) -> AppStore.InboxRequest? {
        if let token = inviteToken(url) { return .invite(token) }
        if isInvitePath(url) { return nil }
        let id = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        return id.isEmpty || id == "/" ? nil : .item(id)
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
