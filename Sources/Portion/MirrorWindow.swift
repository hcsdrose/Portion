import AppKit
import QuartzCore

enum MirrorPlacement: String {
    /// Window is parked just outside the visible desktop. Invisible to you, still shareable.
    case offscreen
    /// Window sits on the *other* half of the screen, behind all other windows.
    case behindWindows
}

/// The window that Zoom / Google Meet share. It shows a live copy of the selected region.
final class MirrorWindowController {
    static let windowTitle = "Portion"

    private var window: NSWindow?
    private let imageLayer = CALayer()

    private var placement: MirrorPlacement = .offscreen

    var isVisible: Bool { window?.isVisible ?? false }

    func show(regionSize: NSSize, sharedRegion: NSRect, on screen: NSScreen, placement: MirrorPlacement) {
        let window = self.window ?? makeWindow()
        self.window = window
        self.placement = placement

        let frame: NSRect
        switch placement {
        case .offscreen:
            // Park it to the right of every connected display.
            let union = NSScreen.screens.reduce(NSRect.null) { $0.union($1.frame) }
            frame = NSRect(x: union.maxX + 200, y: union.minY, width: regionSize.width, height: regionSize.height)
            window.level = .normal
        case .behindWindows:
            // Use the half of the screen that is *not* being shared.
            let f = screen.frame
            let x = sharedRegion.minX <= f.minX ? f.maxX - regionSize.width : f.minX
            frame = NSRect(x: x, y: f.minY, width: regionSize.width, height: regionSize.height)
            window.level = .normal
        }

        window.setFrame(frame, display: true)
        imageLayer.frame = window.contentView?.bounds ?? .zero
        imageLayer.contentsScale = screen.backingScaleFactor

        if placement == .behindWindows {
            window.orderBack(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    func display(_ surface: IOSurface) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = surface
        CATransaction.commit()
    }

    func hide() {
        window?.orderOut(nil)
        imageLayer.contents = nil
    }

    /// Activating Portion (e.g. to show an alert) raises its windows. In the
    /// "behind windows" placement that would cover the user's apps, so push it back.
    func sendToBack() {
        guard placement == .behindWindows, let window, window.isVisible else { return }
        window.orderBack(nil)
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
        window.contentView = view
        return window
    }
}
