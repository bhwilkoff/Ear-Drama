import CoreGraphics
import CoreImage
import Foundation

/// Share on a TV (tvOS-DESIGN §3.6): the TV has no share sheet, so it shows a QR code of the
/// same https twin every other platform's share carries, for a phone in the room to scan.
nonisolated enum ShareCode {
    static func payload(episode id: String) -> String { SiteLinks.episode(id).absoluteString }

    /// The address as words under the code: the twin without its scheme.
    static func shortText(_ url: URL) -> String {
        let text = url.absoluteString
        return text.hasPrefix("https://") ? String(text.dropFirst("https://".count)) : text
    }

    /// Black modules on white, each `scale` pixels square, with no quiet zone of its own (the
    /// view's white plate is the margin). Drawn with nearest-neighbor so the modules stay sharp.
    static func image(_ payload: String, scale: CGFloat = 16) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let code = filter.outputImage else { return nil }
        let scaled = code.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(scaled, from: scaled.extent)
    }
}
