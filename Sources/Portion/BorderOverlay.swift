import AppKit

/// A click-through outline drawn around the region being shared, so you can see what
/// the other people in the call can see. It is excluded from the capture.
final class BorderOverlay {
    private var window: NSWindow?

    func show(around rect: NSRect) {
        let window = self.window ?? makeWindow()
        self.window = window
        window.setFrame(rect, display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.sharingType = .none
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = BorderView()
        return window
    }
}

private final class BorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let lineWidth: CGFloat = 4
        let path = NSBezierPath(rect: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        path.lineWidth = lineWidth
        NSColor.systemRed.withAlphaComponent(0.85).setStroke()
        path.stroke()
    }
}
