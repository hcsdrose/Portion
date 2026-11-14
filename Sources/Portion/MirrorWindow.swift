import AppKit
import QuartzCore

/// The window that Zoom / Google Meet share. It shows a live copy of the selected region.
///
/// It is parked just past the bottom-right corner of the desktop, overlapping it by a single
/// pixel: effectively invisible to you, still shareable. (A window that is *fully* off-screen
/// can't be snapshotted by ScreenCaptureKit, so share pickers would show it blank.)
@MainActor
final class MirrorWindowController {
    nonisolated static let windowTitle = "Portion"

    private var window: NSWindow?
    private let imageLayer = CALayer()
    private let card = IntroCardLayer()
    private var cardTimer: Timer?
    private let shareDetector = ShareDetector()

    /// The intro card covers the live picture after sharing starts, so the window is easy to
    /// spot in Zoom / Meet share pickers. It goes away as soon as the call app starts sharing,
    /// or after this long if that can't be detected (e.g. an app ShareDetector doesn't know).
    static let introCardTimeout: TimeInterval = 60

    var isVisible: Bool { window?.isVisible ?? false }

    func show(regionSize: NSSize, sharedRegion: NSRect, on screen: NSScreen) {
        let window = self.window ?? makeWindow()
        self.window = window
        // Only on a fresh start; switching halves or reconnecting keeps the live picture.
        let isFreshStart = !window.isVisible

        // Hang it off the bottom-right corner of the rightmost display, so only its
        // top-left pixel is on-screen.
        let corner = (NSScreen.screens.max { $0.frame.maxX < $1.frame.maxX } ?? screen).frame
        let frame = NSRect(x: corner.maxX - 1, y: corner.minY - regionSize.height + 1,
                           width: regionSize.width, height: regionSize.height)
        window.level = .normal

        window.setFrame(frame, display: true)
        imageLayer.frame = window.contentView?.bounds ?? .zero
        imageLayer.contentsScale = screen.backingScaleFactor

        if isFreshStart {
            let isLeft = sharedRegion.midX < screen.frame.midX
            showCard(side: isLeft ? .left : .right, in: window.contentView?.bounds ?? .zero,
                     scale: screen.backingScaleFactor)
        } else if !card.isHidden {
            card.layout(in: window.contentView?.bounds ?? .zero, scale: screen.backingScaleFactor)
        }

        window.orderFrontRegardless()
    }

    func display(_ surface: IOSurface) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = surface
        CATransaction.commit()
    }

    func hide() {
        cardTimer?.invalidate()
        cardTimer = nil
        shareDetector.stop()
        window?.orderOut(nil)
        imageLayer.contents = nil
    }

    private func showCard(side: Side, in bounds: CGRect, scale: CGFloat) {
        cardTimer?.invalidate()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        card.configure(side: side)
        card.layout(in: bounds, scale: scale)
        card.opacity = 1
        card.isHidden = false
        CATransaction.commit()

        cardTimer = Timer.scheduledTimer(withTimeInterval: Self.introCardTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeOutCard() }
        }
        shareDetector.start { [weak self] in self?.fadeOutCard() }
    }

    private func fadeOutCard() {
        cardTimer?.invalidate()
        cardTimer = nil
        shareDetector.stop()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        CATransaction.setCompletionBlock { [card] in
            if card.opacity == 0 { card.isHidden = true }
        }
        card.opacity = 0
        CATransaction.commit()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // The title is what Zoom / Meet list in their "share a window" pickers.
        window.title = Self.windowTitle
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.animationBehavior = .none
        // Must stay shareable so other apps can capture it.
        window.sharingType = .readOnly
        // Follow the user across Spaces so it is always "on screen" for the share pickers.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let view = NSView(frame: window.contentRect(forFrameRect: window.frame))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        imageLayer.contentsGravity = .resize
        imageLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        imageLayer.frame = view.bounds
        view.layer?.addSublayer(imageLayer)
        card.isHidden = true
        view.layer?.addSublayer(card)
        window.contentView = view
        return window
    }
}
