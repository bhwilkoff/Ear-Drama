import Foundation

/// The website's addresses: the https twins of the apps' links (DEEP_LINKS.md)
/// and the site pages the Mac's Help menu opens. A share always carries the
/// twin, so a person without the app lands on the web page.
nonisolated enum SiteLinks {
    static let root = URL(string: "https://eardrama.org/")!
    static let credits = URL(string: "https://eardrama.org/credits/")!
    static let privacy = URL(string: "https://eardrama.org/privacy/")!
    static let takedown = URL(string: "https://eardrama.org/takedown/")!

    static func episode(_ id: String) -> URL {
        URL(string: "https://eardrama.org/episode/" + component(id))!
    }

    static func series(_ key: String) -> URL {
        URL(string: "https://eardrama.org/series/" + component(key))!
    }

    /// Percent-encodes exactly as JavaScript's encodeURIComponent, which the
    /// web's 404.html forwarder reverses with decodeURIComponent.
    static func component(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: unreserved) ?? raw
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
}
