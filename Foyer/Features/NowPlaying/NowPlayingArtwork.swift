import AppKit
import CoreImage
import Defaults
import ImageIO
import SwiftUI

// MARK: - Palette

/// A plain RGB triple (0…1), safe to pass between threads.
struct NowPlayingRGB: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    /// Rec.709 luma.
    var luma: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxV = max(red, green, blue)
        let minV = min(red, green, blue)
        let delta = maxV - minV
        var hue = 0.0
        if delta > 0 {
            if maxV == red {
                hue = (green - blue) / delta
                if hue < 0 { hue += 6 }
            } else if maxV == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue /= 6
        }
        let saturation = maxV > 0 ? delta / maxV : 0
        return (hue, saturation, maxV)
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        let h = (hue - floor(hue)) * 6
        let s = min(max(saturation, 0), 1)
        let v = min(max(brightness, 0), 1)
        let i = Int(h) % 6
        let f = h - floor(h)
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))
        switch i {
        case 0: self.init(red: v, green: t, blue: p)
        case 1: self.init(red: q, green: v, blue: p)
        case 2: self.init(red: p, green: v, blue: t)
        case 3: self.init(red: p, green: q, blue: v)
        case 4: self.init(red: t, green: p, blue: v)
        default: self.init(red: v, green: p, blue: q)
        }
    }

    /// Same hue with brightness/saturation moved into a range.
    func adjusted(minBrightness: Double, maxBrightness: Double, saturationScale: Double = 1) -> NowPlayingRGB {
        let c = hsb
        return NowPlayingRGB(hue: c.hue,
                             saturation: min(1, c.saturation * saturationScale),
                             brightness: min(max(c.brightness, minBrightness), maxBrightness))
    }

    func distance(to other: NowPlayingRGB) -> Double {
        let dr = red - other.red, dg = green - other.green, db = blue - other.blue
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
}

/// Colours derived from the artwork (Part C2 §2.2): the most frequent
/// (k-means) cluster is the primary, a distinct second cluster the secondary.
struct NowPlayingPalette: Equatable {
    var primary: NowPlayingRGB?
    var secondary: NowPlayingRGB?
    /// True when the artwork is greyscale (formats then stay grey).
    var isMonochrome: Bool

    static let empty = NowPlayingPalette(primary: nil, secondary: nil, isMonochrome: true)

    /// Waveform tint: the dominant colour lifted so it reads on black.
    var waveformColor: Color {
        guard let primary, !isMonochrome else { return NowPlayingMetrics.Palette.waveformFallback }
        return primary.adjusted(minBrightness: 0.72, maxBrightness: 1, saturationScale: 1.05).color
    }

    /// "Colored" scrubber fill: the primary colour, kept mid-dark like Alcove's.
    var coloredFill: Color {
        guard let primary, !isMonochrome else { return NowPlayingMetrics.Palette.monoFill }
        return primary.adjusted(minBrightness: 0.45, maxBrightness: 0.85, saturationScale: 1.1).color
    }

    /// "Gradient" scrubber fill: darker secondary at the start, primary at the playhead.
    var gradientColors: [Color] {
        guard let primary, !isMonochrome else {
            return [NowPlayingMetrics.Palette.monoFill.opacity(0.55), NowPlayingMetrics.Palette.monoFill]
        }
        let start = (secondary ?? primary).adjusted(minBrightness: 0.3, maxBrightness: 0.5, saturationScale: 1.1)
        let end = primary.adjusted(minBrightness: 0.6, maxBrightness: 0.95, saturationScale: 1.1)
        return [start.color, end.color]
    }
}

// MARK: - Processing

/// Decoded, possibly brightened artwork plus its palette.
struct NowPlayingProcessedArtwork {
    var image: CGImage
    var palette: NowPlayingPalette
}

/// Decodes artwork, extracts its palette and lifts dark artwork (the
/// equivalent of Alcove's `brightenDarkPixels` CIKernel, Part A §6).
enum NowPlayingArtworkProcessor {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Threshold/boost on Rec.709 luma: pixels darker than `threshold` are
    /// lifted by up to `boost`, fading to no change at the threshold.
    private static let brightenKernel: CIColorKernel? = CIColorKernel(source: """
        kernel vec4 brightenDarkPixels(__sample s, float threshold, float boost) {
            float luma = dot(s.rgb, vec3(0.2126, 0.7152, 0.0722));
            float t = clamp((threshold - luma) / max(threshold, 0.0001), 0.0, 1.0);
            vec3 lifted = s.rgb + vec3(boost * t * t) * s.a;
            return vec4(min(lifted, vec3(s.a)), s.a);
        }
        """)

    /// Average luma below which the artwork is considered dark.
    static let darkArtworkLuma = 0.2
    static let brightenThreshold: Float = 0.16
    static let brightenBoost: Float = 0.1

    static func process(_ data: Data) -> NowPlayingProcessedArtwork? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: NowPlayingMetrics.artworkMaxPixel,
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let samples = sample(decoded)
        let palette = extractPalette(from: samples)
        let meanLuma = samples.isEmpty ? 1 : samples.reduce(0) { $0 + $1.luma } / Double(samples.count)

        var image = decoded
        if meanLuma < darkArtworkLuma, let lifted = brighten(decoded) {
            image = lifted
        }
        return NowPlayingProcessedArtwork(image: image, palette: palette)
    }

    private static func brighten(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        var output: CIImage?
        if let kernel = brightenKernel {
            output = kernel.apply(extent: input.extent,
                                  arguments: [input, NSNumber(value: brightenThreshold), NSNumber(value: brightenBoost)])
        }
        if output == nil, let curve = CIFilter(name: "CIToneCurve") {
            // Fallback: lift the shadows with a tone curve.
            curve.setValue(input, forKey: kCIInputImageKey)
            curve.setValue(CIVector(x: 0, y: CGFloat(brightenBoost)), forKey: "inputPoint0")
            curve.setValue(CIVector(x: CGFloat(brightenThreshold), y: CGFloat(brightenThreshold + brightenBoost * 0.6)), forKey: "inputPoint1")
            curve.setValue(CIVector(x: 0.5, y: 0.5), forKey: "inputPoint2")
            curve.setValue(CIVector(x: 0.75, y: 0.75), forKey: "inputPoint3")
            curve.setValue(CIVector(x: 1, y: 1), forKey: "inputPoint4")
            output = curve.outputImage
        }
        guard let output else { return nil }
        return context.createCGImage(output, from: input.extent)
    }

    // MARK: Dominant colours (own k-means)

    private static func sample(_ image: CGImage) -> [NowPlayingRGB] {
        let side = 32
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: base, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }

        var result: [NowPlayingRGB] = []
        result.reserveCapacity(side * side)
        for i in 0..<(side * side) {
            let alpha = Double(bytes[i * 4 + 3]) / 255
            guard alpha > 0.5 else { continue }
            result.append(NowPlayingRGB(red: Double(bytes[i * 4]) / 255 / alpha,
                                        green: Double(bytes[i * 4 + 1]) / 255 / alpha,
                                        blue: Double(bytes[i * 4 + 2]) / 255 / alpha))
        }
        return result
    }

    static func extractPalette(from samples: [NowPlayingRGB]) -> NowPlayingPalette {
        guard samples.count >= 8 else { return .empty }

        let averageSaturation = samples.reduce(0) { $0 + $1.hsb.saturation } / Double(samples.count)
        let clusters = kMeans(samples, k: 5, iterations: 10)
        guard !clusters.isEmpty else { return .empty }

        // Frequency first, nudged toward colourful mid-tones (near-black and
        // near-white clusters make poor tints on a black island).
        func score(_ cluster: (center: NowPlayingRGB, count: Int)) -> Double {
            let c = cluster.center.hsb
            var weight = 0.35 + c.saturation
            if c.brightness < 0.12 { weight *= 0.15 }
            if c.brightness > 0.92 && c.saturation < 0.1 { weight *= 0.4 }
            return Double(cluster.count) * weight
        }
        let ranked = clusters.sorted { score($0) > score($1) }
        let primary = ranked[0].center
        let secondary = ranked.dropFirst().first(where: { $0.center.distance(to: primary) > 0.18 })?.center

        let monochrome = averageSaturation < 0.07 && primary.hsb.saturation < 0.12
        return NowPlayingPalette(primary: primary, secondary: secondary, isMonochrome: monochrome)
    }

    private static func kMeans(_ samples: [NowPlayingRGB], k: Int, iterations: Int) -> [(center: NowPlayingRGB, count: Int)] {
        // Deterministic seeding: spread the initial centres over the luma range.
        let sorted = samples.sorted { $0.luma < $1.luma }
        var centers: [NowPlayingRGB] = (0..<k).map { index in
            let position = (Double(index) + 0.5) / Double(k)
            return sorted[min(sorted.count - 1, Int(position * Double(sorted.count)))]
        }
        var counts = [Int](repeating: 0, count: k)

        for _ in 0..<iterations {
            var sums = [(Double, Double, Double)](repeating: (0, 0, 0), count: k)
            counts = [Int](repeating: 0, count: k)
            for sample in samples {
                var best = 0
                var bestDistance = Double.greatestFiniteMagnitude
                for (index, center) in centers.enumerated() {
                    let d = sample.distance(to: center)
                    if d < bestDistance { bestDistance = d; best = index }
                }
                sums[best].0 += sample.red
                sums[best].1 += sample.green
                sums[best].2 += sample.blue
                counts[best] += 1
            }
            var moved = false
            for index in 0..<k where counts[index] > 0 {
                let n = Double(counts[index])
                let next = NowPlayingRGB(red: sums[index].0 / n, green: sums[index].1 / n, blue: sums[index].2 / n)
                if next.distance(to: centers[index]) > 0.002 { moved = true }
                centers[index] = next
            }
            if !moved { break }
        }

        var result: [(center: NowPlayingRGB, count: Int)] = []
        for index in 0..<k where counts[index] > 0 {
            result.append((center: centers[index], count: counts[index]))
        }
        return result
    }
}

// MARK: - Artwork view

/// Artwork tile with Alcove's track-change transition: a 300 ms Y-axis flip
/// (150 ms in, image swapped edge-on, 150 ms out) when the artwork actually
/// changes, or a crossfade with "Disable artwork flip" (Part C §2.6).
struct NowPlayingArtworkView: View {
    let image: NSImage?
    /// Changes only when the artwork itself changes.
    let identity: Int
    let size: CGFloat
    let cornerRadius: CGFloat

    @Default(.disableAlbumArtFlip) private var disableFlip
    @State private var shownImage: NSImage?
    @State private var shownIdentity: Int
    @State private var angle: Double = 0
    @State private var flipTask: Task<Void, Never>?

    init(image: NSImage?, identity: Int, size: CGFloat, cornerRadius: CGFloat) {
        self.image = image
        self.identity = identity
        self.size = size
        self.cornerRadius = cornerRadius
        _shownImage = State(initialValue: image)
        _shownIdentity = State(initialValue: identity)
    }

    var body: some View {
        ZStack {
            tile(shownImage)
                .id(shownIdentity)
                .transition(.opacity)
        }
        .frame(width: size, height: size)
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        .onChange(of: identity) { _, newValue in
            transition(to: image, identity: newValue)
        }
        .onDisappear {
            flipTask?.cancel()
        }
    }

    @ViewBuilder
    private func tile(_ image: NSImage?) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(shape)
        } else {
            ZStack {
                shape.fill(NowPlayingMetrics.Palette.placeholderBackground)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
            }
            .frame(width: size, height: size)
        }
    }

    private func transition(to newImage: NSImage?, identity newIdentity: Int) {
        guard newIdentity != shownIdentity else { return }
        flipTask?.cancel()

        if disableFlip {
            withAnimation(.easeInOut(duration: Constants.Animations.artworkFlipHalf * 2)) {
                shownImage = newImage
                shownIdentity = newIdentity
            }
            return
        }

        let half = Constants.Animations.artworkFlipHalf
        flipTask = Task { @MainActor in
            withAnimation(.easeIn(duration: half)) { angle = 90 }
            try? await Task.sleep(for: .seconds(half))
            guard !Task.isCancelled else { return }
            var swap = Transaction()
            swap.disablesAnimations = true
            withTransaction(swap) {
                shownImage = newImage
                shownIdentity = newIdentity
            }
            withAnimation(.easeOut(duration: half)) { angle = 0 }
        }
    }
}
