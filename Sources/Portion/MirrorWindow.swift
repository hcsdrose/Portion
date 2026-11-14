import AppKit
import QuartzCore

/// The window that Zoom / Google Meet share. It shows a live copy of the selected region.
///
/// Where it goes depends on the call app (see `show`):
/// - Normally it is parked just past the bottom-right corner of the desktop, overlapping it by
///   a single pixel: invisible to you, still shareable. (A window that is *fully* off-screen
///   can't be snapshotted by ScreenCaptureKit, so share pickers would show it blank.)
/// - Zoom only captures the on-screen part of a window, so it would get that single pixel.
///   For Zoom the window sits exactly over the shared half instead, behind every other window.
///   Portion's capture leaves out its own windows and the window ignores clicks, so where the
///   desktop shows through it shows an exact copy of the desktop: still invisible to you.
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

    /// When Portion starts on its own as a call begins, the user may not open the share picker
    /// for a while, so the card waits for the share instead of timing out. Zoom and Meet are
    /// the apps that trigger this, and ShareDetector recognises both.
    var introCardTimesOut = true

    var isVisible: Bool { window?.isVisible ?? false }

    /// Whether the window is on-screen behind other windows (for Zoom) rather than off-screen.
    private var behindWindows = false

    func show(regionSize: NSSize, sharedRegion: NSRect, on screen: NSScreen, behindWindows: Bool) {
        let window = self.window ?? makeWindow()
        self.window = window
        // Only on a fresh start; switching halves or reconnecting keeps the live picture.
        let isFreshStart = !window.isVisible

        self.behindWindows = behindWindows

        let frame: NSRect
        if behindWindows {
            frame = sharedRegion
        } else {
            // Hang it off the bottom-right corner of the rightmost display, so only its
            // top-left pixel is on-screen.
            let corner = (NSScreen.screens.max { $0.frame.maxX < $1.frame.maxX } ?? screen).frame
            frame = NSRect(x: corner.maxX - 1, y: corner.minY - regionSize.height + 1,
                           width: regionSize.width, height: regionSize.height)
        }
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

        if behindWindows {
            window.orderBack(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    /// Activating Portion (e.g. to show an alert) raises its windows. Behind-windows placement
    /// must never cover the user's apps, so push it back.
    func sendToBack() {
        guard behindWindows, let window, window.isVisible else { return }
        window.orderBack(nil)
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

        if introCardTimesOut {
            cardTimer = Timer.scheduledTimer(withTimeInterval: Self.introCardTimeout, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.fadeOutCard() }
            }
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
