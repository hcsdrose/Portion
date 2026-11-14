// Draws Portion's marketing graphics in the christopherrose.com style (see
// Sources/Portion/Brand.swift):
//   docs/images/          illustrations used in README.md
//   AppStore/screenshots/ Mac App Store screenshots (2880 × 1800)
// Usage (from the repo root):
//   swiftc -parse-as-library Scripts/make-graphics.swift Sources/Portion/IntroCard.swift \
//     Sources/Portion/Brand.swift -o /tmp/make-graphics && /tmp/make-graphics
import AppKit

// Stand-ins for the app types IntroCard.swift refers to.
enum Side { case left, right; var title: String { self == .left ? "Left Half" : "Right Half" } }
enum MirrorWindowController { static let windowTitle = "Portion" }

// MARK: Palette

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

let canvasBG = NSColor.white
let canvasBorder = NSColor(hex: 0xE5E4E7)
let ink = Brand.ink
let inkSoft = Brand.inkSoft
let eyebrow = Brand.label
let line = NSColor(hex: 0xE5E4E7)
let bezel = NSColor(hex: 0x16171D)
let callBG = NSColor(hex: 0x202124)

// MARK: Drawing helpers (top-left origin)

func render(_ name: String, width: CGFloat, height: CGFloat, scale: CGFloat = 2, in dir: String = "docs/images",
            _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.translateBy(x: 0, y: height)
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    let url = URL(fileURLWithPath: "\(dir)/\(name).png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote", url.path)
}

/// Draws `draw` (laid out in its own coordinate space) moved to `origin` and scaled.
func placed(at origin: NSPoint, scale: CGFloat, _ draw: () -> Void) {
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.scaleBy(x: scale, y: scale)
    draw()
    ctx.restoreGState()
}

func fill(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 0) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func stroke(_ rect: NSRect, _ color: NSColor, width: CGFloat, radius: CGFloat = 0, dash: [CGFloat]? = nil) {
    color.setStroke()
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.lineWidth = width
    if let dash { path.setLineDash(dash, count: dash.count, phase: 0) }
    path.stroke()
}

/// The brand gradient (#aa3bff → #ff3bac). Coordinates are flipped, so a positive angle
/// runs towards the lower right, like the site's 120° CSS gradient.
func gradient(_ rect: NSRect, radius: CGFloat, angle: CGFloat = 30) {
    gradient(NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius), angle: angle)
}

func gradient(_ path: NSBezierPath, angle: CGFloat = 30) {
    NSGradient(starting: Brand.purple, ending: Brand.pink)!.draw(in: path, angle: angle)
}

/// A white canvas with the site's hairline border.
func canvas(_ w: CGFloat, _ h: CGFloat) {
    let r = NSRect(x: 0.5, y: 0.5, width: w - 1, height: h - 1)
    fill(r, canvasBG, radius: 28)
    stroke(r, canvasBorder, width: 1, radius: 28)
}

/// A pill "chip" like the ones on christopherrose.com: gradient, solid black, or outlined.
enum ChipStyle { case accent, filled, outlined }

func chip(_ title: String, center: NSPoint, style: ChipStyle, size: CGFloat = 15) {
    let font = Brand.font(size, weight: 700)
    let str = NSAttributedString(string: title, attributes: [.font: font, .kern: size * 0.03])
    let w = str.size().width + size * 2.1, h = size * 2.1
    let r = NSRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    switch style {
    case .accent: gradient(r, radius: h / 2)
    case .filled: fill(r, ink, radius: h / 2)
    case .outlined:
        fill(r, .white, radius: h / 2)
        stroke(r.insetBy(dx: 1, dy: 1), ink, width: 2, radius: h / 2 - 1)
    }
    text(title, at: NSPoint(x: center.x, y: r.minY + (h - size * 1.2) / 2), size: size, weight: 700,
         color: style == .outlined ? ink : .white, align: .center, kern: size * 0.03)
}

func shadowed(blur: CGFloat = 24, y: CGFloat = 8, alpha: CGFloat = 0.18, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: -y)
    s.shadowColor = NSColor.black.withAlphaComponent(alpha)
    s.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

enum Align { case left, center, right }

@discardableResult
func text(_ string: String, at point: NSPoint, size: CGFloat, weight: CGFloat = 400,
          color: NSColor = ink, align: Align = .left, width: CGFloat? = nil, kern: CGFloat = 0) -> NSSize {
    let style = NSMutableParagraphStyle()
    style.alignment = align == .left ? .left : align == .center ? .center : .right
    let attrs: [NSAttributedString.Key: Any] = [
        .font: Brand.font(size, weight: weight), .foregroundColor: color, .paragraphStyle: style, .kern: kern,
    ]
    let str = NSAttributedString(string: string, attributes: attrs)
    let measured = str.size()
    let w = width ?? measured.width
    var x = point.x
    if width == nil {
        if align == .center { x -= w / 2 } else if align == .right { x -= w }
    }
    str.draw(in: NSRect(x: x, y: point.y, width: w, height: measured.height * 3))
    return measured
}

func symbol(_ name: String, in rect: NSRect, color: NSColor, weight: NSFont.Weight = .regular, palette: [NSColor]? = nil) {
    let config = NSImage.SymbolConfiguration(pointSize: rect.height, weight: weight)
        .applying(.init(paletteColors: palette ?? [color]))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return }
    let s = image.size
    let k = min(rect.width / s.width, rect.height / s.height)
    let r = NSRect(x: rect.midX - s.width * k / 2, y: rect.midY - s.height * k / 2, width: s.width * k, height: s.height * k)
    image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

func circleBadge(_ n: Int, center: NSPoint, radius: CGFloat) {
    let rect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    gradient(NSBezierPath(ovalIn: rect))
    let size = radius * 1.1
    text("\(n)", at: NSPoint(x: center.x, y: center.y - size * 0.62), size: size, weight: 700, color: .white, align: .center)
}

// MARK: Pieces of fake UI

/// A slide-like document: what you want people to see.
func drawDocument(in r: NSRect) {
    fill(r, .white)
    let pad = r.width * 0.09
    var y = r.minY + pad
    fill(NSRect(x: r.minX + pad, y: y, width: r.width * 0.55, height: r.height * 0.06), ink, radius: 4)
    y += r.height * 0.11
    for w in [0.8, 0.7, 0.75] {
        fill(NSRect(x: r.minX + pad, y: y, width: (r.width - pad * 2) * w, height: r.height * 0.025), line, radius: 3)
        y += r.height * 0.05
    }
    y += r.height * 0.03
    // Bar chart.
    let chart = NSRect(x: r.minX + pad, y: y, width: r.width - pad * 2, height: r.maxY - pad - y)
    let bars: [CGFloat] = [0.45, 0.7, 0.55, 0.9]
    let gap = chart.width * 0.06
    let bw = (chart.width - gap * CGFloat(bars.count - 1)) / CGFloat(bars.count)
    for (i, h) in bars.enumerated() {
        let bh = chart.height * h
        let bar = NSRect(x: chart.minX + CGFloat(i) * (bw + gap), y: chart.maxY - bh, width: bw, height: bh)
        gradient(NSBezierPath(roundedRect: bar, xRadius: 4, yRadius: 4), angle: 90)
    }
}

/// Email / chat: the private stuff you keep to yourself.
func drawPrivateSide(in r: NSRect) {
    fill(r, NSColor(hex: 0xEEF0F5))
    let pad = r.width * 0.08
    var y = r.minY + pad
    let rowH = (r.height - pad * 2) / 5
    for i in 0..<5 {
        let row = NSRect(x: r.minX + pad, y: y, width: r.width - pad * 2, height: rowH - pad * 0.5)
        fill(row, .white, radius: 6)
        let dot = min(row.height * 0.5, 22)
        let colors: [UInt32] = [0xFF9F0A, 0x34C759, 0xFF375F, 0x5E5CE6, 0x64D2FF]
        fill(NSRect(x: row.minX + 8, y: row.midY - dot / 2, width: dot, height: dot), NSColor(hex: colors[i]), radius: dot / 2)
        fill(NSRect(x: row.minX + dot + 18, y: row.midY - 7, width: row.width * 0.35, height: 5), ink.withAlphaComponent(0.6), radius: 2)
        fill(NSRect(x: row.minX + dot + 18, y: row.midY + 3, width: row.width * 0.55, height: 4), line, radius: 2)
        y += rowH
    }
}

func drawMonitor(_ screen: NSRect) {
    shadowed { fill(screen.insetBy(dx: -14, dy: -14), bezel, radius: 18) }
    // Stand.
    let neck = NSRect(x: screen.midX - 40, y: screen.maxY + 14, width: 80, height: 40)
    fill(neck, NSColor(hex: 0xB9BCC6))
    fill(NSRect(x: screen.midX - 110, y: neck.maxY, width: 220, height: 12), NSColor(hex: 0xA5A9B5), radius: 6)
}

// MARK: Images

@main
struct MakeGraphics {
    static func main() {
        try? FileManager.default.createDirectory(atPath: "docs/images", withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: "AppStore/screenshots", withIntermediateDirectories: true)
        hero()
        steps()
        card()
        menu()
        appStoreScreenshots()
    }

    /// Your screen → what the call sees.
    static func hero() {
        render("how-it-works", width: 1200, height: 590) {
            canvas(1200, 590)
            heroScene()
        }
    }

    /// The hero illustration without its canvas, laid out in a 1200 × 590 space.
    static func heroScene() {
        do {

            // Your screen.
            let screen = NSRect(x: 70, y: 110, width: 500, height: 312)
            drawMonitor(screen)
            let half = NSRect(x: screen.minX, y: screen.minY, width: screen.width / 2, height: screen.height)
            drawDocument(in: half)
            drawPrivateSide(in: NSRect(x: half.maxX, y: screen.minY, width: screen.width / 2, height: screen.height))
            let ring = NSBezierPath(rect: half)
            ring.append(NSBezierPath(rect: half.insetBy(dx: 6, dy: 6)))
            ring.windingRule = .evenOdd
            gradient(ring)
            chip("Shared", center: NSPoint(x: half.midX, y: half.maxY + 2), style: .accent)
            chip("Private", center: NSPoint(x: half.maxX + half.width / 2, y: half.maxY + 2), style: .filled)
            text("YOUR SCREEN", at: NSPoint(x: screen.midX, y: 30), size: 14, weight: 700, color: eyebrow, align: .center, kern: 2.2)
            text("You pick a half", at: NSPoint(x: screen.midX, y: 52), size: 30, weight: 800, align: .center)
            text("A colored outline shows what's shared.", at: NSPoint(x: screen.midX, y: 516),
                 size: 18, color: inkSoft, align: .center)

            // Arrow.
            let arrowY: CGFloat = 266
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 616, y: arrowY))
            path.line(to: NSPoint(x: 724, y: arrowY))
            path.lineWidth = 8
            path.lineCapStyle = .round
            Brand.purple.setStroke()
            path.stroke()
            let head = NSBezierPath()
            head.move(to: NSPoint(x: 744, y: arrowY))
            head.line(to: NSPoint(x: 716, y: arrowY - 20))
            head.line(to: NSPoint(x: 716, y: arrowY + 20))
            head.close()
            Brand.pink.setFill()
            head.fill()

            // The call.
            let call = NSRect(x: 790, y: 96, width: 340, height: 340)
            shadowed { fill(call, callBG, radius: 18) }
            for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
                fill(NSRect(x: call.minX + 16 + CGFloat(i) * 20, y: call.minY + 16, width: 12, height: 12), NSColor(hex: UInt32(c)), radius: 6)
            }
            let shared = NSRect(x: call.minX + 60, y: call.minY + 44, width: 220, height: 220 * 312 / 250)
            drawDocument(in: NSRect(x: shared.minX, y: shared.minY, width: shared.width, height: min(shared.height, 238)))
            // Participant tiles.
            for i in 0..<3 {
                let t = NSRect(x: call.minX + 46 + CGFloat(i) * 86, y: call.maxY - 50, width: 76, height: 38)
                fill(t, NSColor(hex: 0x3C4043), radius: 6)
                symbol("person.fill", in: t.insetBy(dx: 20, dy: 8), color: NSColor(hex: 0x9AA0A6))
            }
            text("WHAT THE CALL SEES", at: NSPoint(x: call.midX, y: 30), size: 14, weight: 700, color: eyebrow, align: .center, kern: 2.2)
            text("Only that half", at: NSPoint(x: call.midX, y: 52), size: 30, weight: 800, align: .center)
            text("Everything else stays private.", at: NSPoint(x: call.midX, y: 516),
                 size: 18, color: inkSoft, align: .center)
        }
    }

    /// Three steps: pick a half, pick the Portion window, click Share.
    static func steps() {
        render("three-steps", width: 1200, height: 470) {
            canvas(1200, 470)
            let panelW: CGFloat = 352, gap: CGFloat = 22, top: CGFloat = 40
            let titles = ["Pick a half", "Choose “Portion”", "Click Share"]
            let notes = ["Click the Portion icon in your menu bar.",
                         "In Zoom or Meet, pick the Portion window.",
                         "Done! The card goes away and your half is live."]
            for i in 0..<3 {
                let p = NSRect(x: 40 + CGFloat(i) * (panelW + gap), y: top, width: panelW, height: 390)
                shadowed(blur: 16, y: 4, alpha: 0.06) { fill(p, .white, radius: 20) }
                stroke(p, canvasBorder, width: 1, radius: 20)
                circleBadge(i + 1, center: NSPoint(x: p.minX + 44, y: p.minY + 42), radius: 22)
                text("STEP \(i + 1)", at: NSPoint(x: p.minX + 80, y: p.minY + 18), size: 12, weight: 700, color: eyebrow, kern: 2)
                text(titles[i], at: NSPoint(x: p.minX + 80, y: p.minY + 34), size: 24, weight: 800)
                let art = NSRect(x: p.minX + 24, y: p.minY + 84, width: p.width - 48, height: 210)
                switch i {
                case 0: stepMenu(art)
                case 1: stepPicker(art)
                default: stepShare(art)
                }
                text(notes[i], at: NSPoint(x: p.minX + 24, y: p.maxY - 76), size: 17, color: inkSoft, width: p.width - 48)
            }
        }
    }

    static func stepMenu(_ r: NSRect) {
        // Menu bar strip.
        let bar = NSRect(x: r.minX, y: r.minY, width: r.width, height: 34)
        fill(bar, NSColor(hex: 0xE6E8EF), radius: 8)
        for (i, s) in ["wifi", "battery.75percent", "clock"].enumerated() {
            symbol(s, in: NSRect(x: bar.maxX - 34 - CGFloat(i) * 30, y: bar.minY + 9, width: 22, height: 16), color: inkSoft)
        }
        let iconBox = NSRect(x: bar.minX + 120, y: bar.minY + 3, width: 36, height: 28)
        fill(iconBox, Brand.purple.withAlphaComponent(0.15), radius: 6)
        symbol("rectangle.split.2x1", in: iconBox.insetBy(dx: 7, dy: 6), color: ink)
        // Dropdown.
        let menu = NSRect(x: iconBox.minX - 10, y: bar.maxY + 8, width: 190, height: 140)
        shadowed(blur: 14, y: 4, alpha: 0.16) { fill(menu, .white, radius: 10) }
        let rows = [("rectangle.lefthalf.filled", "Share Left Half"), ("rectangle.righthalf.filled", "Share Right Half"), ("", "Stop Sharing")]
        for (i, row) in rows.enumerated() {
            let rr = NSRect(x: menu.minX + 6, y: menu.minY + 10 + CGFloat(i) * 40, width: menu.width - 12, height: 34)
            if i == 0 { gradient(rr, radius: rr.height / 2) }
            let color: NSColor = i == 0 ? .white : (i == 2 ? inkSoft : ink)
            if !row.0.isEmpty { symbol(row.0, in: NSRect(x: rr.minX + 10, y: rr.minY + 9, width: 22, height: 16), color: color) }
            text(row.1, at: NSPoint(x: rr.minX + 40, y: rr.minY + 7), size: 15, weight: 500, color: color)
        }
    }

    static func stepPicker(_ r: NSRect) {
        fill(r, NSColor(hex: 0x35363A), radius: 12)
        text("Choose what to share", at: NSPoint(x: r.minX + 16, y: r.minY + 12), size: 14, weight: 600, color: .white)
        let tileW: CGFloat = (r.width - 16 * 3) / 2, tileH: CGFloat = 110
        for i in 0..<2 {
            let t = NSRect(x: r.minX + 16 + CGFloat(i) * (tileW + 16), y: r.minY + 48, width: tileW, height: tileH)
            if i == 0 {
                gradient(t, radius: 6)
                let g = NSRect(x: t.midX - 22, y: t.minY + 22, width: 44, height: 27)
                fill(g, NSColor.white.withAlphaComponent(0.3), radius: 4)
                fill(NSRect(x: g.minX, y: g.minY, width: g.width / 2, height: g.height), .white, radius: 4)
                stroke(g, .white, width: 2, radius: 4)
                text("Portion", at: NSPoint(x: t.midX, y: t.minY + 58), size: 20, weight: 800, color: .white, align: .center)
                stroke(t.insetBy(dx: -5, dy: -5), NSColor(hex: 0x8AB4F8), width: 3, radius: 9)
            } else {
                fill(t, NSColor(hex: 0x1F1F1F), radius: 6)
                for k in 0..<5 {
                    fill(NSRect(x: t.minX + 12, y: t.minY + 14 + CGFloat(k) * 18, width: t.width * (k % 2 == 0 ? 0.7 : 0.5), height: 6),
                         NSColor(hex: 0x5F6368), radius: 3)
                }
            }
        }
        text("Portion", at: NSPoint(x: r.minX + 16 + tileW / 2, y: r.minY + 168), size: 13, color: .white, align: .center)
        text("Other window", at: NSPoint(x: r.minX + 32 + tileW * 1.5, y: r.minY + 168), size: 13,
             color: NSColor(hex: 0xBDC1C6), align: .center)
    }

    static func stepShare(_ r: NSRect) {
        fill(r, NSColor(hex: 0x35363A), radius: 12)
        let cancel = NSRect(x: r.maxX - 230, y: r.minY + 24, width: 96, height: 40)
        let share = NSRect(x: r.maxX - 122, y: r.minY + 24, width: 104, height: 40)
        stroke(cancel, NSColor(hex: 0x8AB4F8), width: 1.5, radius: 20)
        text("Cancel", at: NSPoint(x: cancel.midX, y: cancel.minY + 10), size: 16, weight: 500, color: NSColor(hex: 0x8AB4F8), align: .center)
        fill(share, NSColor(hex: 0x8AB4F8), radius: 20)
        text("Share", at: NSPoint(x: share.midX, y: share.minY + 10), size: 16, weight: 600, color: NSColor(hex: 0x202124), align: .center)
        symbol("cursorarrow", in: NSRect(x: share.midX + 6, y: share.midY + 2, width: 28, height: 34), color: .white)
        // Result: "You're presenting".
        let banner = NSRect(x: r.minX + 18, y: r.minY + 100, width: r.width - 36, height: 90)
        fill(banner, NSColor(hex: 0x1E3A2B), radius: 10)
        symbol("checkmark.circle.fill", in: NSRect(x: banner.minX + 16, y: banner.midY - 18, width: 36, height: 36), color: NSColor(hex: 0x34C759),
               palette: [.white, NSColor(hex: 0x34C759)])
        text("You're presenting", at: NSPoint(x: banner.minX + 64, y: banner.minY + 22), size: 18, weight: 600, color: .white)
        text("only the half you picked", at: NSPoint(x: banner.minX + 64, y: banner.minY + 48), size: 14, color: NSColor(hex: 0xA8DAB5))
    }

    /// The card Portion shows in share pickers, straight from the app's own drawing code.
    static func card() {
        let size = CGSize(width: 520, height: 400), scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        ctx.scaleBy(x: scale, y: scale)
        ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: 24, cornerHeight: 24, transform: nil))
        ctx.clip()
        let layer = IntroCardLayer()
        layer.configure(side: .left)
        layer.layout(in: CGRect(origin: .zero, size: size), scale: scale)
        layer.render(in: ctx)
        let url = URL(fileURLWithPath: "docs/images/portion-card.png")
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
        print("wrote", url.path)
    }

    /// The menu bar menu.
    static func menu() {
        render("menu", width: 560, height: 470) {
            canvas(560, 470)
            menuScene()
        }
    }

    /// The menu without its canvas, laid out in a 560 × 470 space (menu at 60, 40, 440 × 390).
    static func menuScene() {
        do {
            let m = NSRect(x: 60, y: 40, width: 440, height: 390)
            shadowed(blur: 20, y: 6, alpha: 0.16) { fill(m, .white, radius: 12) }
            stroke(m, line, width: 1, radius: 12)
            var y = m.minY + 12
            func row(_ title: String, icon: String? = nil, check: Bool = false, chevron: Bool = false,
                     disabled: Bool = false, highlight: Bool = false) {
                let r = NSRect(x: m.minX + 8, y: y, width: m.width - 16, height: 32)
                if highlight { gradient(r, radius: r.height / 2) }
                let color: NSColor = highlight ? .white : disabled ? inkSoft : ink
                if check { symbol("checkmark", in: NSRect(x: r.minX + 10, y: r.minY + 9, width: 14, height: 14), color: color, weight: .bold) }
                if let icon { symbol(icon, in: NSRect(x: r.minX + 32, y: r.minY + 8, width: 22, height: 16), color: color) }
                text(title, at: NSPoint(x: r.minX + (icon == nil ? 34 : 62), y: r.minY + 6), size: 15, color: color)
                if chevron { symbol("chevron.right", in: NSRect(x: r.maxX - 22, y: r.minY + 10, width: 10, height: 12), color: color, weight: .semibold) }
                y += 32
            }
            func separator() {
                fill(NSRect(x: m.minX + 16, y: y + 5, width: m.width - 32, height: 1), line)
                y += 11
            }
            row("Not sharing", disabled: true)
            separator()
            row("Share Left Half", icon: "rectangle.lefthalf.filled", highlight: true)
            row("Share Right Half", icon: "rectangle.righthalf.filled")
            row("Stop Sharing", disabled: true)
            separator()
            row("Display", chevron: true)
            row("Outline Shared Area", check: true)
            row("Portion Window Placement", chevron: true)
            separator()
            row("Launch at Login", check: true)
            row("Quit Portion")
        }
    }
}

// MARK: - Mac App Store screenshots (1440 × 900 points, rendered at 2880 × 1800)

extension MakeGraphics {
    static let shotW: CGFloat = 1440, shotH: CGFloat = 900

    static func appStoreScreenshots() {
        screenshot("01-share-half", eyebrow: "PORTION FOR MAC",
                   headline: [("Share ", false), ("half", true), (" your screen.", false)],
                   subline: "Present one half in your video call. Keep the other half to yourself.") {
            placed(at: NSPoint(x: 120, y: 280), scale: 1) { heroScene() }
        }

        screenshot("02-find-it", eyebrow: "EASY TO PICK",
                   headline: [("Find it ", false), ("instantly", true), (".", false)],
                   subline: "Portion shows up as a bold card in your call's window list. Click Share and it's live.") {
            let scale: CGFloat = 2.55
            let size = NSSize(width: 304 * scale, height: 210 * scale)
            placed(at: NSPoint(x: (shotW - size.width) / 2, y: 290), scale: scale) {
                stepPicker(NSRect(x: 0, y: 0, width: 304, height: 210))
            }
        }

        screenshot("03-private", eyebrow: "PRIVATE BY DESIGN",
                   headline: [("Everything else ", true), ("stays private.", false)],
                   subline: "An outline shows exactly what's shared. Email, chat and notifications on the other half stay yours.") {
            placed(at: NSPoint(x: (shotW - 500 * 1.5) / 2, y: 300), scale: 1.5) { privacyScene() }
        }

        screenshot("04-menu-bar", eyebrow: "ONE CLICK",
                   headline: [("Lives in your ", false), ("menu bar", true), (".", false)],
                   subline: "No windows, no clutter. Pick a half, switch sides or stop, right from the menu bar.") {
            menuBarScene()
        }

        screenshot("05-switch", eyebrow: "NO RESHARING",
                   headline: [("Switch halves ", false), ("mid-call", true), (".", false)],
                   subline: "Jump from your slides to your demo. The call keeps going, with no need to share again.") {
            switchScene()
        }
    }

    /// A white, softly glowing slide with a centered eyebrow, headline and subline.
    static func screenshot(_ name: String, eyebrow label: String, headline parts: [(String, Bool)],
                           subline: String, art: () -> Void) {
        render(name, width: shotW, height: shotH, in: "AppStore/screenshots") {
            fill(NSRect(x: 0, y: 0, width: shotW, height: shotH), .white)
            glow(center: NSPoint(x: 120, y: 60), radius: 620, color: Brand.purple)
            glow(center: NSPoint(x: shotW - 80, y: shotH - 40), radius: 640, color: Brand.pink)
            text(label, at: NSPoint(x: shotW / 2, y: 70), size: 17, weight: 700, color: eyebrow, align: .center, kern: 3)
            headline(parts, centerX: shotW / 2, y: 98, size: 68)
            text(subline, at: NSPoint(x: shotW / 2, y: 196), size: 25, color: inkSoft, align: .center)
            art()
        }
    }

    static func glow(center: NSPoint, radius: CGFloat, color: NSColor) {
        NSGradient(colors: [color.withAlphaComponent(0.13), color.withAlphaComponent(0)])!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
    }

    /// A Rubik headline where accent words are filled with the brand gradient, like the site's
    /// `.home-accent-word`.
    static func headline(_ parts: [(String, Bool)], centerX: CGFloat, y: CGFloat, size: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: Brand.font(size, weight: 800), .kern: -size * 0.02]
        let strings = parts.map { NSAttributedString(string: $0.0, attributes: attrs) }
        let total = strings.reduce(0) { $0 + $1.size().width }
        var x = centerX - total / 2
        for (str, part) in zip(strings, parts) {
            let sz = str.size()
            let rect = NSRect(x: x, y: y, width: ceil(sz.width), height: ceil(sz.height))
            if part.1 {
                // Clip to the glyph outlines, then paint the gradient through them.
                let line = CTLineCreateWithAttributedString(str)
                var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
                let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
                let ctx = NSGraphicsContext.current!.cgContext
                ctx.saveGState()
                // Our canvas is flipped; Core Text wants y up, with the baseline at the origin.
                let baseline = rect.minY + (sz.height - (ascent + descent)) / 2 + ascent
                ctx.translateBy(x: rect.minX, y: baseline)
                ctx.scaleBy(x: 1, y: -1)
                ctx.textMatrix = .identity
                ctx.textPosition = .zero
                ctx.setTextDrawingMode(.clip)
                CTLineDraw(line, ctx)
                let colors = [Brand.purple.cgColor, Brand.pink.cgColor] as CFArray
                let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: ascent), end: CGPoint(x: width, y: -descent), options: [])
                ctx.restoreGState()
            } else {
                let plain = NSMutableAttributedString(attributedString: str)
                plain.addAttribute(.foregroundColor, value: ink, range: NSRange(location: 0, length: plain.length))
                plain.draw(at: rect.origin)
            }
            x += sz.width
        }
    }

    /// A monitor sharing one half: document on the shared side, private apps on the other.
    static func monitor(_ screen: NSRect, shared side: Side, chips: Bool = true, chipSize: CGFloat = 15,
                        sharedLabel: String = "Shared", privateLabel: String = "Private") {
        drawMonitor(screen)
        let left = NSRect(x: screen.minX, y: screen.minY, width: screen.width / 2, height: screen.height)
        let right = NSRect(x: left.maxX, y: screen.minY, width: screen.width / 2, height: screen.height)
        let (sharedHalf, privateHalf) = side == .left ? (left, right) : (right, left)
        drawDocument(in: sharedHalf)
        drawPrivateSide(in: privateHalf)
        let ring = NSBezierPath(rect: sharedHalf)
        ring.append(NSBezierPath(rect: sharedHalf.insetBy(dx: 6, dy: 6)))
        ring.windingRule = .evenOdd
        gradient(ring)
        if chips {
            chip(sharedLabel, center: NSPoint(x: sharedHalf.midX, y: screen.maxY + 2), style: .accent, size: chipSize)
            chip(privateLabel, center: NSPoint(x: privateHalf.midX, y: screen.maxY + 2), style: .filled, size: chipSize)
        }
    }

    /// Shared document on the left; a notification arriving on the private right half.
    static func privacyScene() {
        let screen = NSRect(x: 0, y: 0, width: 500, height: 312)
        monitor(screen, shared: .left)
        let note = NSRect(x: screen.maxX - 214, y: screen.minY + 12, width: 202, height: 58)
        shadowed(blur: 12, y: 3, alpha: 0.18) { fill(note, NSColor.white.withAlphaComponent(0.97), radius: 12) }
        let icon = NSRect(x: note.minX + 10, y: note.midY - 15, width: 30, height: 30)
        fill(icon, NSColor(hex: 0x34C759), radius: 8)
        symbol("message.fill", in: icon.insetBy(dx: 6, dy: 7), color: .white)
        text("Messages", at: NSPoint(x: icon.maxX + 10, y: note.minY + 10), size: 12, weight: 700)
        text("Dinner at 7? 🍝", at: NSPoint(x: icon.maxX + 10, y: note.minY + 29), size: 12, color: inkSoft)
        symbol("eye.slash.fill", in: NSRect(x: note.maxX - 30, y: note.minY + 10, width: 18, height: 14), color: Brand.purple)
    }

    /// A Mac menu bar across the slide, with the Portion menu open below its icon.
    static func menuBarScene() {
        let bar = NSRect(x: 200, y: 290, width: shotW - 400, height: 40)
        shadowed(blur: 10, y: 2, alpha: 0.08) { fill(bar, NSColor(hex: 0xF2F1F4), radius: 12) }
        symbol("apple.logo", in: NSRect(x: bar.minX + 22, y: bar.minY + 10, width: 18, height: 20), color: ink)
        var itemX = bar.minX + 62
        for (i, item) in ["Finder", "File", "Edit", "View", "Go", "Window", "Help"].enumerated() {
            let w = text(item, at: NSPoint(x: itemX, y: bar.minY + 10), size: 16, weight: i == 0 ? 700 : 400).width
            itemX += w + 26
        }
        text("Tue 9:41 AM", at: NSPoint(x: bar.maxX - 20, y: bar.minY + 10), size: 16, weight: 500, align: .right)
        for (i, s) in ["wifi", "battery.75percent", "magnifyingglass"].enumerated() {
            symbol(s, in: NSRect(x: bar.maxX - 170 - CGFloat(i) * 40, y: bar.minY + 11, width: 24, height: 18), color: ink)
        }
        let iconBox = NSRect(x: bar.maxX - 330, y: bar.minY + 4, width: 44, height: 32)
        gradient(iconBox, radius: 8)
        symbol("rectangle.split.2x1", in: iconBox.insetBy(dx: 10, dy: 8), color: .white)
        // The menu (menuScene's menu sits at 60, 40, 440 wide in its own space), right-aligned
        // under the icon, as macOS does near the edge of the screen.
        let scale: CGFloat = 1.22
        let menuLeft = iconBox.maxX - 440 * scale
        placed(at: NSPoint(x: menuLeft - 60 * scale, y: bar.maxY + 6 - 40 * scale), scale: scale) { menuScene() }
    }

    /// Two monitors: sharing the left half, then the right, with the call carrying on.
    static func switchScene() {
        let w: CGFloat = 470, h: CGFloat = 294, y: CGFloat = 340
        monitor(NSRect(x: 120, y: y, width: w, height: h), shared: .left, sharedLabel: "Slides", privateLabel: "Notes")
        monitor(NSRect(x: shotW - 120 - w, y: y, width: w, height: h), shared: .right, sharedLabel: "Demo", privateLabel: "Notes")
        // Two-way arrow between them.
        let midY = y + h / 2, x0: CGFloat = 120 + w + 40, x1 = shotW - 120 - w - 40
        let shaft = NSBezierPath()
        shaft.move(to: NSPoint(x: x0 + 18, y: midY))
        shaft.line(to: NSPoint(x: x1 - 18, y: midY))
        shaft.lineWidth = 8
        shaft.lineCapStyle = .round
        Brand.purple.setStroke()
        shaft.stroke()
        for (tip, dir) in [(x0, CGFloat(1)), (x1, CGFloat(-1))] {
            let head = NSBezierPath()
            head.move(to: NSPoint(x: tip, y: midY))
            head.line(to: NSPoint(x: tip + 26 * dir, y: midY - 18))
            head.line(to: NSPoint(x: tip + 26 * dir, y: midY + 18))
            head.close()
            (dir > 0 ? Brand.purple : Brand.pink).setFill()
            head.fill()
        }
        chip("Still sharing", center: NSPoint(x: shotW / 2, y: midY + 50), style: .outlined, size: 16)
    }
}
