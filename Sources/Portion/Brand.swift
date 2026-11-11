import AppKit
import CoreText

/// Portion's look, matched to christopherrose.com: black and white, a purple-to-pink
/// accent gradient, and the Rubik typeface.
enum Brand {
    static let purple = NSColor(srgbRed: 0xAA / 255.0, green: 0x3B / 255.0, blue: 0xFF / 255.0, alpha: 1) // #aa3bff
    static let pink = NSColor(srgbRed: 0xFF / 255.0, green: 0x3B / 255.0, blue: 0xAC / 255.0, alpha: 1)   // #ff3bac
    static let ink = NSColor.black
    static let inkSoft = NSColor(srgbRed: 0x55 / 255.0, green: 0x55 / 255.0, blue: 0x55 / 255.0, alpha: 1) // #555
    static let label = NSColor(srgbRed: 0x99 / 255.0, green: 0x99 / 255.0, blue: 0x99 / 255.0, alpha: 1)   // #999

    /// The site's accent gradient (CSS `linear-gradient(120deg, #aa3bff, #ff3bac)`).
    static var gradientColors: [CGColor] { [purple.cgColor, pink.cgColor] }

    /// Start/end points for a CAGradientLayer approximating CSS's 120° (towards lower right).
    static let gradientStart = CGPoint(x: 0, y: 0.8)
    static let gradientEnd = CGPoint(x: 1, y: 0.2)

    // MARK: Rubik

    private static let registered: Bool = {
        let candidates = [
            Bundle.main.url(forResource: "Rubik", withExtension: "ttf", subdirectory: "Fonts"),
            Bundle.main.url(forResource: "Rubik", withExtension: "ttf"),
            // `swift run` / scripts run from the repo root.
            URL(fileURLWithPath: "Resources/Fonts/Rubik.ttf"),
        ]
        guard let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) })
        else { return false }
        var error: Unmanaged<CFError>?
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) || NSFont(name: "Rubik", size: 12) != nil
    }()

    /// Rubik at the given weight (400 regular, 700 bold, 800 extra bold), falling back to the
    /// system font if the bundled font is missing.
    static func font(_ size: CGFloat, weight: CGFloat = 400) -> NSFont {
        guard registered, let base = NSFont(name: "Rubik", size: size) else {
            return .systemFont(ofSize: size, weight: weight >= 800 ? .heavy : weight >= 700 ? .bold : weight >= 500 ? .medium : .regular)
        }
        let wghtAxis = 0x77676874 // 'wght'
        let descriptor = base.fontDescriptor.addingAttributes([
            NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wghtAxis: weight],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}
