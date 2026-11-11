// Renders Portion's app icon into an .iconset folder.
// Usage: swift Scripts/make-icon.swift <output.iconset>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // Background squircle.
    let inset = s * 0.1
    let bg = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bgPath = NSBezierPath(roundedRect: bg, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.98, alpha: 1),
               ending: NSColor(calibratedRed: 0.38, green: 0.22, blue: 0.85, alpha: 1))!
        .draw(in: bgPath, angle: -60)

    // Screen outline.
    let screen = bg.insetBy(dx: s * 0.13, dy: s * 0.19)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: s * 0.04, yRadius: s * 0.04)
    NSColor.white.withAlphaComponent(0.35).setFill()
    screenPath.fill()

    // Highlighted left half.
    let half = NSRect(x: screen.minX, y: screen.minY, width: screen.width / 2, height: screen.height)
    NSGraphicsContext.current?.saveGraphicsState()
    screenPath.addClip()
    NSColor.white.setFill()
    half.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    screenPath.lineWidth = max(1, s * 0.025)
    NSColor.white.setStroke()
    screenPath.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: outDir.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: outDir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
