import AppKit
import CoreAudio
import CoreGraphics
import Foundation
import os

let callLog = Logger(subsystem: "com.christopherrose.Portion", category: "calls")

/// Whether a window from `CGWindowListCopyWindowInfo` belongs to Zoom. Zoom's process name has
/// changed over the years ("zoom.us", "Zoom"), so this goes by its bundle identifier.
func isZoomWindow(_ info: [String: Any]) -> Bool {
    guard let pid = info[kCGWindowOwnerPID as String] as? pid_t else { return false }
    return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "us.zoom.xos"
}

/// Notices when a Zoom meeting or Google Meet call is open, so Portion can start sharing
/// before the user opens the call app's share picker.
///
/// Like `ShareDetector`, this reads on-screen window titles, which Portion can see because it
/// already has Screen Recording permission. Nothing is stored or sent anywhere.
@MainActor
final class CallDetector {
    enum Event {
        /// A call Portion hadn't seen yet is on screen.
        case callStarted
        /// The user opened Meet's share picker: they're about to present.
        case sharePickerOpened
        /// No call has been seen for a while.
        case callEnded
    }

    var onEvent: ((Event) -> Void)?
    var isInCall: Bool { currentCall != nil }
    var isZoomCall: Bool { currentCall == "zoom" }

    /// A call counts as over once its window, the call app's sharing indicator and microphone
    /// use have all been gone this long.
    ///
    /// Browsers only expose the *active* tab's title, so a Meet call also vanishes from view
    /// while the user is on another tab. The microphone usually stays open during a call (even
    /// when muted), which keeps it going. If a quiet background call does end early, it starts
    /// again as soon as its tab is back in front, and it never ends while sharing.
    private static let endGrace: TimeInterval = 3

    /// Meet's tab title during a call, e.g. "Meet - abc-defg-hij". The code identifies the call.
    private static let meetTitle = try! NSRegularExpression(
        pattern: #"\bMeet [-–] ([a-z]{3,4}-[a-z]{4}-[a-z]{3,4})\b"#)
    private static let meetPickerTitle = "Choose what to share with meet.google.com"

    private var timer: Timer?
    /// Identifies the call in progress ("meet:abc-defg-hij" or "zoom"), nil when none.
    private var currentCall: String?
    private var lastSeen: Date?
    private var pickerWasOpen = false
    private var micWasInUse: Bool?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        poll()
    }

    private func poll() {
        guard CGPreflightScreenCaptureAccess() else { return }
        let now = Date()
        let seen = Self.scan()
        let micInUse = Self.microphoneInUse()
        if micInUse != micWasInUse {
            micWasInUse = micInUse
            callLog.notice("microphone in use: \(micInUse, privacy: .public)")
        }

        if let call = seen.call {
            lastSeen = now
            if call != currentCall {
                currentCall = call
                emit(.callStarted, call)
            }
        } else if currentCall != nil, ShareDetector.isSharing() || micInUse {
            // These could come from any site or app, so they only keep a call that was already
            // seen going (e.g. while presenting, or talking, from another tab).
            lastSeen = now
        }

        if seen.pickerOpen && !pickerWasOpen {
            lastSeen = now
            if currentCall == nil { currentCall = "meet" }
            emit(.sharePickerOpened, currentCall ?? "")
        }
        pickerWasOpen = seen.pickerOpen

        if currentCall != nil, let lastSeen, now.timeIntervalSince(lastSeen) >= Self.endGrace {
            let ended = currentCall ?? ""
            currentCall = nil
            emit(.callEnded, ended)
        }
    }

    private func emit(_ event: Event, _ call: String) {
        callLog.notice("\(String(describing: event), privacy: .public) \(call, privacy: .public)")
        onEvent?(event)
    }

    /// Whether any app is using any microphone right now.
    private static func microphoneInUse() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return false }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return false }

        for device in devices {
            // Only devices with input channels are microphones.
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioDevicePropertyScopeInput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { continue }

            var running = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            var isRunning: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &running, 0, nil, &runningSize, &isRunning) == noErr,
               isRunning != 0 {
                return true
            }
        }
        return false
    }

    private static func scan() -> (call: String?, pickerOpen: Bool) {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return (nil, false)
        }
        var call: String?
        var pickerOpen = false
        for info in list {
            guard let title = info[kCGWindowName as String] as? String, !title.isEmpty else { continue }
            if title.hasPrefix(meetPickerTitle) {
                pickerOpen = true
            } else if title.hasPrefix("Zoom Meeting") || title.hasPrefix("Zoom Webinar"), isZoomWindow(info) {
                call = call ?? "zoom"
            } else if let match = meetTitle.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                      let code = Range(match.range(at: 1), in: title) {
                call = call ?? "meet:\(title[code])"
            }
        }
        return (call, pickerOpen)
    }
}
