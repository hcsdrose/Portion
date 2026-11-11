import AppKit
import QuartzCore

/// A bold, branded card drawn over the mirror for the first few seconds of sharing, so the
/// Portion window is easy to pick out in Zoom / Meet "share a window" thumbnails.
/// Styled after the app icon: blue-to-purple gradient, a screen with the shared half lit.
final class IntroCardLayer: CAGradientLayer {
    private let screenLayer = CAShapeLayer()
    private let sharedHalf = CAShapeLayer()
    private let titleLayer = CATextLayer()
    private let subtitleLayer = CATextLayer()
    private var side: Side = .left

    override init() {
        super.init()
        colors = [
            NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.98, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.38, green: 0.22, blue: 0.85, alpha: 1).cgColor,
        ]
        startPoint = CGPoint(x: 0, y: 1)
        endPoint = CGPoint(x: 1, y: 0)

        screenLayer.fillColor = NSColor.white.withAlphaComponent(0.3).cgColor
        screenLayer.strokeColor = NSColor.white.cgColor
        sharedHalf.fillColor = NSColor.white.cgColor
        screenLayer.addSublayer(sharedHalf)
        addSublayer(screenLayer)

        for layer in [titleLayer, subtitleLayer] {
            layer.alignmentMode = .center
            layer.foregroundColor = NSColor.white.cgColor
            layer.truncationMode = .end
            addSublayer(layer)
        }
        titleLayer.string = MirrorWindowController.windowTitle
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(side: Side) {
        self.side = side
        subtitleLayer.string = "Sharing \(side.title.lowercased())"
    }

    /// Sizes everything relative to the window so it reads well even as a tiny thumbnail.
    func layout(in bounds: CGRect, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        frame = bounds
        let unit = min(bounds.width, bounds.height * 0.8)

        // Screen glyph.
        let glyphW = unit * 0.55
        let glyphH = glyphW * 0.62
        let titleSize = unit * 0.18
        let subtitleSize = unit * 0.065
        let titleH = ceil(titleSize * 1.25)
        let subtitleH = ceil(subtitleSize * 1.35)
        let gap1 = unit * 0.08
        let gap2 = unit * 0.01
        let total = glyphH + gap1 + titleH + gap2 + subtitleH

        // Layer coordinates have a bottom-left origin; lay out from the top of the stack down.
        var top = bounds.midY + total / 2

        top -= glyphH
        let glyphRect = CGRect(x: bounds.midX - glyphW / 2, y: top, width: glyphW, height: glyphH)
        let radius = glyphW * 0.06
        screenLayer.frame = glyphRect
        let local = CGRect(origin: .zero, size: glyphRect.size)
        screenLayer.path = CGPath(roundedRect: local, cornerWidth: radius, cornerHeight: radius, transform: nil)
        screenLayer.lineWidth = max(2, unit * 0.012)

        let halfRect = CGRect(x: side == .left ? 0 : local.midX, y: 0, width: local.width / 2, height: local.height)
        let mask = CAShapeLayer()
        mask.path = screenLayer.path
        sharedHalf.frame = local
        sharedHalf.path = CGPath(rect: halfRect, transform: nil)
        sharedHalf.mask = mask

        top -= gap1 + titleH
        titleLayer.font = NSFont.systemFont(ofSize: titleSize, weight: .heavy)
        titleLayer.fontSize = titleSize
        titleLayer.frame = CGRect(x: 0, y: top, width: bounds.width, height: titleH)

        top -= gap2 + subtitleH
        subtitleLayer.font = NSFont.systemFont(ofSize: subtitleSize, weight: .semibold)
        subtitleLayer.fontSize = subtitleSize
        subtitleLayer.frame = CGRect(x: 0, y: top, width: bounds.width, height: subtitleH)

        for layer in [self, screenLayer, sharedHalf, titleLayer, subtitleLayer] {
            layer.contentsScale = scale
        }
    }
}
