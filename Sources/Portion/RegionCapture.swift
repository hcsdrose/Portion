import AppKit
import CoreMedia
import ScreenCaptureKit

enum PortionError: LocalizedError {
    case displayNotFound

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "The selected display could not be found."
        }
    }
}

/// Captures a rectangle of a display with ScreenCaptureKit and hands each new frame
/// (as an IOSurface) to `onFrame` on the main thread.
@MainActor
final class RegionCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((IOSurface) -> Void)?
    var onError: ((Error) -> Void)?

    private var stream: SCStream?
    private nonisolated let queue = DispatchQueue(label: "portion.capture", qos: .userInteractive)

    var isRunning: Bool { stream != nil }

    /// Starts capturing, or retargets the running stream so the same mirror window keeps
    /// being shared without interruption.
    /// - Parameters:
    ///   - sourceRect: region in the display's own point space (origin top-left).
    ///   - scale: backing scale factor of the display (2 on Retina).
    func start(displayID: CGDirectDisplayID, sourceRect: CGRect, scale: CGFloat) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw PortionError.displayNotFound
        }

        // Exclude our own windows (border overlay, mirror window) so they never show up
        // inside the shared picture and can't cause a hall-of-mirrors effect.
        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == pid }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = max(2, Int((sourceRect.width * scale).rounded()))
        config.height = max(2, Int((sourceRect.height * scale).rounded()))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = true
        // The mirror keeps showing the latest frame's surface after we receive it, so leave
        // headroom in the pool; a tighter queue risks a displayed surface being overwritten.
        config.queueDepth = 6

        if let stream {
            try await stream.updateContentFilter(filter)
            try await stream.updateConfiguration(config)
            return
        }

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await newStream.startCapture()
        stream = newStream
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }

    // MARK: SCStreamOutput

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }

        Task { @MainActor [weak self] in
            self?.onFrame?(surface)
        }
    }

    // MARK: SCStreamDelegate

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil
            self.onError?(error)
        }
    }
}
