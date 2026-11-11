import AppKit
import ScreenCaptureKit
import ServiceManagement

enum Side: String {
    case left, right

    var title: String { self == .left ? "Left Half" : "Right Half" }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let capture = RegionCapture()
    private let mirror = MirrorWindowController()
    private let border = BorderOverlay()

    /// The half being shared. Stays set while reconnecting after an interruption.
    private var activeSide: Side?
    /// The shared area in AppKit coordinates, used to redraw the outline.
    private var activeRegion: NSRect?
    private var pendingStarts = 0
    private var isRecovering = false
    private var screensAsleep = false
    private var sessionInactive = false

    /// Start/stop requests run one after another so they can never overlap.
    private var lastOperation: Task<Void, Never>?

    private static let maxRecoveryAttempts = 3

    private let defaults = UserDefaults.standard

    private var showBorder: Bool {
        get { defaults.object(forKey: "showBorder") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showBorder") }
    }

    private var placement: MirrorPlacement {
        get { MirrorPlacement(rawValue: defaults.string(forKey: "placement") ?? "") ?? .offscreen }
        set { defaults.set(newValue.rawValue, forKey: "placement") }
    }

    /// Display chosen in the menu; nil means "the screen with the menu bar".
    private var preferredDisplayID: CGDirectDisplayID? {
        get { (defaults.object(forKey: "displayID") as? NSNumber)?.uint32Value }
        set { defaults.set(newValue.map { NSNumber(value: $0) }, forKey: "displayID") }
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()

        capture.onFrame = { [weak self] surface in
            self?.mirror.display(surface)
        }
        capture.onError = { [weak self] error in
            self?.handleStreamError(error)
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screensDidSleep),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidWake),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionDidResignActive),
                              name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionDidBecomeActive),
                              name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        if !CGPreflightScreenCaptureAccess() {
            // Triggers the system prompt on first launch.
            CGRequestScreenCaptureAccess()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        mirror.sendToBack()
    }

    func applicationWillTerminate(_ notification: Notification) {
        border.hide()
        mirror.hide()
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        for side in [Side.left, .right] {
            let item = NSMenuItem(title: "Share \(side.title)", action: #selector(shareSide(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = side.rawValue
            item.state = activeSide == side ? .on : .off
            item.image = NSImage(systemSymbolName: side == .left ? "rectangle.lefthalf.filled" : "rectangle.righthalf.filled",
                                 accessibilityDescription: nil)
            menu.addItem(item)
        }

        let canStop = activeSide != nil || pendingStarts > 0
        let stop = NSMenuItem(title: "Stop Sharing", action: canStop ? #selector(stopSharing) : nil, keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)
        menu.addItem(.separator())

        if NSScreen.screens.count > 1 {
            let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let current = targetScreen()
            for screen in NSScreen.screens {
                let item = NSMenuItem(title: screen.localizedName, action: #selector(chooseDisplay(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = NSNumber(value: screen.displayID)
                item.state = screen.displayID == current.displayID ? .on : .off
                sub.addItem(item)
            }
            displayItem.submenu = sub
            menu.addItem(displayItem)
        }

        let borderItem = NSMenuItem(title: "Outline Shared Area", action: #selector(toggleBorder), keyEquivalent: "")
        borderItem.target = self
        borderItem.state = showBorder ? .on : .off
        menu.addItem(borderItem)

        let placementItem = NSMenuItem(title: "Portion Window Placement", action: nil, keyEquivalent: "")
        let placementMenu = NSMenu()
        for (option, title) in [(MirrorPlacement.offscreen, "Hidden Off-Screen (Recommended)"),
                                (MirrorPlacement.behindWindows, "On Other Half, Behind Windows")] {
            let item = NSMenuItem(title: title, action: #selector(choosePlacement(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = placement == option ? .on : .off
            placementMenu.addItem(item)
        }
        placementItem.submenu = placementMenu
        menu.addItem(placementItem)

        let help = NSMenuItem(title: "How to Share in Zoom / Meet…", action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        menu.addItem(help)
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: "Quit Portion", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private var statusText: String {
        if pendingStarts > 0 { return "Starting…" }
        guard let side = activeSide else { return "Not sharing" }
        if isRecovering { return "Reconnecting \(side.title.lowercased())…" }
        return "Sharing \(side.title.lowercased()) → share the “\(MirrorWindowController.windowTitle)” window"
    }

    private func updateStatusIcon() {
        let symbol: String
        switch activeSide {
        case .left: symbol = "rectangle.lefthalf.filled"
        case .right: symbol = "rectangle.righthalf.filled"
        case nil: symbol = "rectangle.split.2x1"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Portion")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = activeSide.map { "Portion – sharing \($0.title.lowercased())" } ?? "Portion"
    }

    // MARK: Actions

    @objc private func shareSide(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let side = Side(rawValue: raw) else { return }
        startSharing(side)
    }

    @objc private func stopSharing() {
        enqueue { [weak self] in await self?.endSharing() }
    }

    @objc private func chooseDisplay(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.uint32Value else { return }
        preferredDisplayID = id
        if let side = activeSide { startSharing(side) }
    }

    @objc private func toggleBorder() {
        showBorder.toggle()
        // The outline is never captured, so there's no need to touch the stream.
        if showBorder, let region = activeRegion { border.show(around: region) } else { border.hide() }
    }

    @objc private func choosePlacement(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = MirrorPlacement(rawValue: raw) else { return }
        placement = value
        if let side = activeSide { startSharing(side) }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            presentAlert(title: "Couldn’t change Launch at Login",
                         message: "\(error.localizedDescription)\n\nMake sure Portion is in your Applications folder.")
        }
    }

    @objc private func showHelp() {
        presentAlert(title: "Sharing half your screen", message: """
        1. Choose “Share Left Half” or “Share Right Half” from the Portion menu bar icon.
        2. In Zoom: click Share Screen and pick the window named “Portion”.
           In Google Meet (Chrome): click Present → A window, and pick “Portion”.
        3. Everyone in the call now sees only that half of your screen. Switch halves any time from the menu; the call keeps sharing the same window.

        Tip: if “Portion” doesn’t appear in the picker, set Portion Window Placement to “On Other Half, Behind Windows” and try again.
        """)
    }

    @objc private func screensChanged() {
        guard let side = activeSide else { return }
        startSharing(side)
    }

    @objc private func screensDidSleep() { screensAsleep = true }
    @objc private func sessionDidResignActive() { sessionInactive = true }

    @objc private func screensDidWake() {
        screensAsleep = false
        resumeIfInterrupted()
    }

    @objc private func sessionDidBecomeActive() {
        sessionInactive = false
        resumeIfInterrupted()
    }

    // MARK: Sharing

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = lastOperation
        lastOperation = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    private func startSharing(_ side: Side) {
        guard ensurePermission() else { return }
        pendingStarts += 1
        enqueue { [weak self] in
            guard let self else { return }
            defer { self.pendingStarts -= 1 }
            do {
                try await self.beginCapture(side)
            } catch {
                await self.endSharing()
                self.presentAlert(title: "Couldn’t start sharing", message: """
                \(error.localizedDescription)

                Make sure Portion is allowed under System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen Portion.
                """)
            }
        }
    }

    /// Positions our windows and starts (or retargets) the capture stream.
    private func beginCapture(_ side: Side) async throws {
        let screen = targetScreen()
        let frame = screen.frame
        let leftWidth = floor(frame.width / 2)
        let width = side == .left ? leftWidth : frame.width - leftWidth
        let xOffset = side == .left ? 0 : leftWidth

        // ScreenCaptureKit wants display-local points with a top-left origin.
        let sourceRect = CGRect(x: xOffset, y: 0, width: width, height: frame.height)
        // AppKit (bottom-left origin, global coordinates) for our own windows.
        let cocoaRect = NSRect(x: frame.minX + xOffset, y: frame.minY, width: width, height: frame.height)

        if showBorder { border.show(around: cocoaRect) } else { border.hide() }
        mirror.show(regionSize: cocoaRect.size, sharedRegion: cocoaRect, on: screen, placement: placement)

        try await capture.start(displayID: screen.displayID, sourceRect: sourceRect,
                                scale: screen.backingScaleFactor)
        activeSide = side
        activeRegion = cocoaRect
        isRecovering = false
        updateStatusIcon()
    }

    private func endSharing() async {
        activeSide = nil
        activeRegion = nil
        isRecovering = false
        border.hide()
        mirror.hide()
        updateStatusIcon()
        await capture.stop()
    }

    // MARK: Recovery

    private func handleStreamError(_ error: Error) {
        guard activeSide != nil else { return }
        // The user ended capture from the system's screen-recording indicator: respect that.
        if (error as? SCStreamError)?.code == .userStopped {
            enqueue { [weak self] in await self?.endSharing() }
            return
        }
        scheduleRecovery(attempt: 1)
    }

    /// Tries to restart a stream that stopped on its own (sleep, lock, display change…),
    /// keeping the same mirror window so the call doesn't need to re-share.
    private func scheduleRecovery(attempt: Int) {
        guard let side = activeSide else { return }
        isRecovering = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
            self?.enqueue { [weak self] in await self?.recover(side, attempt: attempt) }
        }
    }

    private func recover(_ side: Side, attempt: Int) async {
        // Someone stopped or switched sides meanwhile, or another restart already worked.
        guard activeSide == side, !capture.isRunning else { return }
        do {
            try await beginCapture(side)
        } catch {
            if screensAsleep || sessionInactive {
                return // Try again when the screen wakes or the user logs back in.
            }
            if attempt < Self.maxRecoveryAttempts {
                scheduleRecovery(attempt: attempt + 1)
            } else {
                await endSharing()
                presentAlert(title: "Sharing stopped", message: error.localizedDescription)
            }
        }
    }

    private func resumeIfInterrupted() {
        guard activeSide != nil, !capture.isRunning else { return }
        scheduleRecovery(attempt: 1)
    }

    // MARK: Helpers

    private func targetScreen() -> NSScreen {
        if let id = preferredDisplayID, let screen = NSScreen.screens.first(where: { $0.displayID == id }) {
            return screen
        }
        return NSScreen.screens.first ?? NSScreen.main!
    }

    private func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = """
        Portion needs permission to see your screen so it can mirror half of it.

        Turn on Portion under Privacy & Security → Screen & System Audio Recording, then quit and reopen Portion.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if runModal(alert) == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    /// Shows an alert on the next run-loop turn, so a pending start/stop is never
    /// held up waiting for the user to dismiss it.
    private func presentAlert(title: String, message: String) {
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            _ = self?.runModal(alert)
        }
    }

    @discardableResult
    private func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        mirror.sendToBack()
        let response = alert.runModal()
        mirror.sendToBack()
        return response
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }
}
