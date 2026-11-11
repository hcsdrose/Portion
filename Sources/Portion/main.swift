import AppKit

// Top-level code runs on the main thread; tell the compiler so it can create the
// main-actor-isolated delegate.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
    // NSApplication holds its delegate weakly; keep ours alive for the app's lifetime.
    withExtendedLifetime(delegate) { app.run() }
}
