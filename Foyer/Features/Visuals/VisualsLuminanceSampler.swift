import AppKit
import CoreGraphics
import Defaults
import ImageIO
import SwiftUI

/// Samples the luminance of whatever sits behind the island and publishes
/// `NotchController.shared.backdropIsDark`, which gates the contrast outline
/// (Part D §6: the ~1.5 px white stroke is drawn over dark backdrops only).
///
/// Mirrors Alcove's `WallpaperChangeMonitor`: the current desktop picture for
/// the screen is decoded and the region of the image that maps under the
/// notch is measured, honouring the wallpaper's scaling and fill colour. It
/// never captures the screen, so it never triggers a Screen Recording prompt.
/// Samples are Rec. 709 luma, averaged over all target screens, re-evaluated
/// every ~20 s (the observed latency) and after wallpaper/space changes.
@MainActor
final class VisualsLuminanceSampler {
    static let shared = VisualsLuminanceSampler()

    private var timer: Timer?
    private var debounceTask: Task<Void, Never>?
    private var sampleTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var centerObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var defaultsObservation: Defaults.Observation?
    private var isRunning = false
    /// Last aggregated luma (0…1); nil until the first successful sample.
    private(set) var luminance: Double?

    private init() {}

    // MARK: Lifecycle

    func start() {
        if defaultsObservation == nil {
            defaultsObservation = Defaults.observe(.contrastOutline, options: []) { _ in
                Task { @MainActor in VisualsLuminanceSampler.shared.applyEnabledState() }
            }
        }
        applyEnabledState()
    }

    func stop() {
        defaultsObservation?.invalidate()
        defaultsObservation = nil
        stopSampling()
    }

    private func applyEnabledState() {
        if Defaults[.contrastOutline] {
            startSampling()
        } else {
            stopSampling()
        }
    }

    private func startSampling() {
        guard !isRunning else { return }
        isRunning = true

        let interval = VisualsConstants.luminanceResampleInterval
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in VisualsLuminanceSampler.shared.sampleNow() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                        object: nil, queue: .main) { _ in
            Task { @MainActor in VisualsLuminanceSampler.shared.scheduleResample() }
        })
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                                        object: nil, queue: .main) { _ in
            Task { @MainActor in VisualsLuminanceSampler.shared.scheduleResample() }
        })
        centerObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                      object: nil, queue: .main) { _ in
            Task { @MainActor in VisualsLuminanceSampler.shared.scheduleResample() }
        })
        // Posted by the Dock / System Settings when the desktop picture changes.
        distributedObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.desktop"), object: nil, queue: .main) { _ in
            Task { @MainActor in VisualsLuminanceSampler.shared.scheduleResample() }
        })

        // First evaluation shortly after launch, once the panels exist.
        scheduleResample(after: 1)
    }

    private func stopSampling() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        debounceTask?.cancel()
        debounceTask = nil
        sampleTask?.cancel()
        sampleTask = nil
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspace.removeObserver($0) }
        workspaceObservers.removeAll()
        centerObservers.forEach { NotificationCenter.default.removeObserver($0) }
        centerObservers.removeAll()
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        distributedObservers.removeAll()
    }

    /// Debounced re-sample after an environment change.
    private func scheduleResample(after delay: Double = VisualsConstants.luminanceResampleInterval) {
        guard isRunning else { return }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            VisualsLuminanceSampler.shared.sampleNow()
        }
    }

    // MARK: Sampling

    func sampleNow() {
        guard isRunning else { return }
        let screens = NotchWindowManager.targetScreens()
        guard !screens.isEmpty else { return }

        let captured: [Double] = []
        var wallpaperRequests: [VisualsWallpaperRequest] = []

        // Wallpaper only: screen capture (even with permission already
        // granted) makes macOS 15+ show its recurring "bypass the private
        // window picker" confirmation, which isn't worth it for an outline.
        for screen in screens {
            if let request = wallpaperRequest(for: screen) {
                wallpaperRequests.append(request)
            }
        }

        if wallpaperRequests.isEmpty {
            publish(captured)
            return
        }

        sampleTask?.cancel()
        let requests = wallpaperRequests
        let alreadyCaptured = captured
        sampleTask = Task { @MainActor in
            let wallpaperLumas = await Task.detached(priority: .utility) { () -> [Double] in
                requests.compactMap { VisualsWallpaperLuma.measure($0) }
            }.value
            guard !Task.isCancelled else { return }
            VisualsLuminanceSampler.shared.publish(alreadyCaptured + wallpaperLumas)
        }
    }

    private func publish(_ samples: [Double]) {
        guard !samples.isEmpty else { return }
        let luma = samples.reduce(0, +) / Double(samples.count)
        luminance = luma

        let controller = NotchController.shared
        let wasDark = controller.backdropIsDark
        let isDark: Bool
        if wasDark {
            isDark = luma < VisualsConstants.lightThreshold
        } else {
            isDark = luma < VisualsConstants.darkThreshold
        }
        guard isDark != wasDark else { return }
        withAnimation(VisualsConstants.outlineFade) {
            controller.backdropIsDark = isDark
        }
    }

    /// Region around the island in AppKit global coordinates.
    private func sampleRect(on screen: NSScreen) -> CGRect {
        let size = VisualsConstants.sampleSize
        let frame = screen.frame
        let width = min(size.width, frame.width)
        let height = min(size.height, frame.height)
        return CGRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height)
    }

    // MARK: Wallpaper path

    private func wallpaperRequest(for screen: NSScreen) -> VisualsWallpaperRequest? {
        let workspace = NSWorkspace.shared
        guard let url = workspace.desktopImageURL(for: screen) else { return nil }
        let options = workspace.desktopImageOptions(for: screen) ?? [:]

        var scaling = NSImageScaling.scaleProportionallyUpOrDown
        if let raw = options[.imageScaling] as? NSNumber, let value = NSImageScaling(rawValue: raw.uintValue) {
            scaling = value
        }
        let allowClipping = (options[.allowClipping] as? NSNumber)?.boolValue ?? true
        var fillLuma: Double?
        if let fill = options[.fillColor] as? NSColor {
            fillLuma = VisualsLumaMath.luma(of: fill)
        }

        let frame = screen.frame
        let rect = sampleRect(on: screen)
        // Sample rect in screen-local, top-left-origin points.
        let local = CGRect(x: rect.minX - frame.minX,
                           y: frame.maxY - rect.maxY,
                           width: rect.width,
                           height: rect.height)
        return VisualsWallpaperRequest(url: url,
                                       screenSize: frame.size,
                                       backingScale: screen.backingScaleFactor,
                                       sampleRect: local,
                                       scalingRaw: scaling.rawValue,
                                       allowClipping: allowClipping,
                                       fillLuma: fillLuma)
    }
}

// MARK: - Off-main wallpaper measurement

/// Everything needed to measure a desktop picture off the main actor.
struct VisualsWallpaperRequest: Sendable {
    var url: URL
    var screenSize: CGSize
    var backingScale: CGFloat
    var sampleRect: CGRect
    var scalingRaw: UInt
    var allowClipping: Bool
    var fillLuma: Double?
}

enum VisualsWallpaperLuma {
    /// Maps the sample rect onto the desktop picture as the Dock draws it and
    /// returns the coverage-weighted luma (image + fill colour).
    static func measure(_ request: VisualsWallpaperRequest) -> Double? {
        guard let thumb = VisualsWallpaperCache.shared.thumbnail(for: request.url) else {
            return request.fillLuma
        }
        let image = thumb.image
        let originalSize = thumb.originalPixelSize
        let screen = request.screenSize
        guard screen.width > 0, screen.height > 0, originalSize.width > 0, originalSize.height > 0 else { return nil }

        // Size of the picture as drawn on the screen (points).
        let scaling = NSImageScaling(rawValue: request.scalingRaw) ?? .scaleProportionallyUpOrDown
        let pointSize = CGSize(width: originalSize.width / max(request.backingScale, 1),
                               height: originalSize.height / max(request.backingScale, 1))
        let fit = min(screen.width / originalSize.width, screen.height / originalSize.height)
        let fill = max(screen.width / originalSize.width, screen.height / originalSize.height)
        var drawn: CGSize
        switch scaling {
        case .scaleAxesIndependently:
            drawn = screen
        case .scaleNone:
            drawn = pointSize
        case .scaleProportionallyDown:
            let scale = min(1, min(screen.width / pointSize.width, screen.height / pointSize.height))
            drawn = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)
        case .scaleProportionallyUpOrDown:
            let scale = request.allowClipping ? fill : fit
            drawn = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
        @unknown default:
            drawn = CGSize(width: originalSize.width * fill, height: originalSize.height * fill)
        }
        guard drawn.width > 0, drawn.height > 0 else { return request.fillLuma }

        // Drawn picture rect, centred on the screen (top-left origin).
        let drawnRect = CGRect(x: (screen.width - drawn.width) / 2,
                               y: (screen.height - drawn.height) / 2,
                               width: drawn.width,
                               height: drawn.height)
        let sample = request.sampleRect
        let overlap = sample.intersection(drawnRect)
        let sampleArea = sample.width * sample.height
        guard sampleArea > 0 else { return nil }

        var imageLuma: Double?
        var coverage: Double = 0
        if !overlap.isNull, overlap.width > 0, overlap.height > 0 {
            // Map the overlap into thumbnail pixel coordinates (top-left origin).
            let sx = CGFloat(image.width) / drawnRect.width
            let sy = CGFloat(image.height) / drawnRect.height
            var pixelRect = CGRect(x: (overlap.minX - drawnRect.minX) * sx,
                                   y: (overlap.minY - drawnRect.minY) * sy,
                                   width: overlap.width * sx,
                                   height: overlap.height * sy).integral
            pixelRect = pixelRect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            if !pixelRect.isNull, pixelRect.width >= 1, pixelRect.height >= 1 {
                imageLuma = VisualsLumaMath.averageLuma(of: image, region: pixelRect)
                coverage = Double((overlap.width * overlap.height) / sampleArea)
            }
        }

        switch (imageLuma, request.fillLuma) {
        case let (fromImage?, fromFill?):
            return fromImage * coverage + fromFill * (1 - coverage)
        case let (fromImage?, nil):
            return fromImage
        case let (nil, fromFill?):
            return fromFill
        case (nil, nil):
            return nil
        }
    }
}

/// Decoded desktop-picture thumbnails keyed by URL and modification date.
final class VisualsWallpaperCache: @unchecked Sendable {
    static let shared = VisualsWallpaperCache()

    struct Thumbnail {
        let image: CGImage
        let originalPixelSize: CGSize
    }

    private struct Entry {
        let modified: Date?
        let thumbnail: Thumbnail
    }

    private let lock = NSLock()
    private var entries: [URL: Entry] = [:]

    func thumbnail(for url: URL) -> Thumbnail? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        lock.lock()
        if let entry = entries[url], entry.modified == modified {
            lock.unlock()
            return entry.thumbnail
        }
        lock.unlock()

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }

        var originalSize = CGSize.zero
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let w = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
            let h = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            // Orientations 5-8 swap width and height.
            originalSize = orientation >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: VisualsConstants.wallpaperThumbnailMaxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        if originalSize.width <= 0 || originalSize.height <= 0 {
            originalSize = CGSize(width: image.width, height: image.height)
        }

        let thumbnail = Thumbnail(image: image, originalPixelSize: originalSize)
        lock.lock()
        // One desktop picture per display at most; keep the cache tiny.
        if entries.count >= 4 { entries.removeAll() }
        entries[url] = Entry(modified: modified, thumbnail: thumbnail)
        lock.unlock()
        return thumbnail
    }
}

// MARK: - Luma math

enum VisualsLumaMath {
    /// Rec. 709 luma of a colour in sRGB (0…1).
    static func luma(of color: NSColor) -> Double? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return luma(r: Double(srgb.redComponent), g: Double(srgb.greenComponent), b: Double(srgb.blueComponent))
    }

    static func luma(r: Double, g: Double, b: Double) -> Double {
        VisualsConstants.lumaRed * r + VisualsConstants.lumaGreen * g + VisualsConstants.lumaBlue * b
    }

    /// Average Rec. 709 luma of `image` (optionally cropped to `region`, in
    /// pixel coordinates with a top-left origin), measured on a small
    /// downsampled sRGB bitmap. Transparent pixels count as black.
    static func averageLuma(of image: CGImage, region: CGRect?) -> Double? {
        var source = image
        if let region, let cropped = image.cropping(to: region) {
            source = cropped
        }
        let width = VisualsConstants.sampleBitmapWidth
        let height = VisualsConstants.sampleBitmapHeight
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let drewImage: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .medium
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drewImage else { return nil }

        var total: Double = 0
        let count = width * height
        for i in 0..<count {
            let o = i * 4
            total += luma(r: Double(pixels[o]) / 255, g: Double(pixels[o + 1]) / 255, b: Double(pixels[o + 2]) / 255)
        }
        return total / Double(count)
    }
}
