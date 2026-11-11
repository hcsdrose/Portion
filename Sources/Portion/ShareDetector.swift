import CoreGraphics
import Foundation

/// Notices when a call app *starts* sharing, so the intro card can get out of the way.
///
/// macOS doesn't tell an app when another app begins capturing its window, so this watches
/// for the on-screen indicator windows that call apps open once sharing begins. Window
/// titles are readable because Portion already has Screen Recording permission.
/// Cancelling a share picker opens no indicator, so the card stays up for the next try.
@MainActor
final class ShareDetector {
    /// Title fragments of windows that appear only once a share has started.
    private static let sharingIndicators: [(owner: String?, title: String)] = [
        // Chrome / Edge / Brave bar: "meet.google.com is sharing a window."
        (nil, " is sharing a"),
        // Zoom's floating toolbar while sharing.
        ("Zoom", "zoom share toolbar window"),
    ]

    private var timer: Timer?
    /// Indicators already on screen when watching began (e.g. an earlier share in another
    /// tab), which mustn't count as a new share.
    private var baseline: Set<CGWindowID> = []

    func start(onShareStarted: @escaping @MainActor () -> Void) {
        stop()
        baseline = Self.indicatorWindows()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !Self.indicatorWindows().subtracting(self.baseline).isEmpty {
                    self.stop()
                    onShareStarted()
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private static func indicatorWindows() -> Set<CGWindowID> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var found: Set<CGWindowID> = []
        for info in list {
            guard let title = info[kCGWindowName as String] as? String, !title.isEmpty,
                  let id = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            let owner = info[kCGWindowOwnerName as String] as? String
            let matches = sharingIndicators.contains { indicator in
                (indicator.owner == nil || indicator.owner == owner) && title.contains(indicator.title)
            }
            if matches { found.insert(id) }
        }
        return found
    }
}
