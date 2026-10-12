import Accelerate
import AppKit
import AudioToolbox
import Combine
import CoreAudio
import Defaults
import Foundation

// MARK: - Permission (kTCCServiceAudioCapture)

/// Audio-capture permission through TCC's private preflight/request calls
/// (Part F §1: `TCCAccessPreflight` / `TCCAccessRequest(kTCCServiceAudioCapture)`).
enum NowPlayingAudioCapturePermission {
    enum Status: Equatable { case granted, denied, notDetermined, unknown }

    private typealias PreflightFn = @convention(c) (CFString, CFDictionary?) -> Int32
    private typealias RequestFn = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")

    static func preflight() -> Status {
        guard let fn = PrivateAPI.symbol("TCCAccessPreflight", in: PrivateAPI.tcc, as: PreflightFn.self) else {
            return .unknown
        }
        switch fn(service, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .notDetermined
        }
    }

    /// Asks TCC; falls back to opening System Settings › Privacy › Audio Capture.
    @MainActor
    static func request(_ completion: @escaping @MainActor (Bool) -> Void) {
        Defaults[.hasPromptedAudioPermission] = true
        guard let fn = PrivateAPI.symbol("TCCAccessRequest", in: PrivateAPI.tcc, as: RequestFn.self) else {
            openSettings()
            completion(false)
            return
        }
        fn(service, nil) { granted in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if !granted { openSettings() }
                    completion(granted)
                }
            }
        }
    }

    @MainActor
    static func openSettings() {
        if let settingsURL { NSWorkspace.shared.open(settingsURL) }
    }
}

// MARK: - Core Audio helpers

/// Small Core Audio property helpers. Selectors introduced with process taps
/// (macOS 14.2) are spelled as four-char codes.
enum NowPlayingCoreAudio {
    static func fourCC(_ code: String) -> AudioObjectPropertySelector {
        var result: UInt32 = 0
        for scalar in code.unicodeScalars.prefix(4) {
            result = (result << 8) | (scalar.value & 0xFF)
        }
        return result
    }

    static let translatePIDToProcessObject = fourCC("id2p")
    static let processObjectList = fourCC("prs#")
    static let processPID = fourCC("ppid")
    static let processBundleID = fourCC("pbid")
    static let tapUIDSelector = fourCC("tuid")
    static let tapFormatSelector = fourCC("tfmt")

    static func propertyAddress(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func processObject(for pid: pid_t) -> AudioObjectID? {
        var address = propertyAddress(translatePIDToProcessObject)
        var pidValue = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pidValue, &size, &object)
        guard status == noErr, object != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return object
    }

    static func processObjects() -> [AudioObjectID] {
        var address = propertyAddress(processObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = objects.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return -1 }
            return AudioObjectGetPropertyData(system, &address, 0, nil, &size, base)
        }
        return status == noErr ? objects : []
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = propertyAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func defaultOutputDevice() -> AudioObjectID? {
        var address = propertyAddress(kAudioHardwarePropertyDefaultSystemOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return device
    }

    static func tapFormat(_ tap: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = propertyAddress(tapFormatSelector)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format)
        return status == noErr ? format : nil
    }

    /// Process objects to tap for a source: the app itself, its helpers
    /// (bundle ids prefixed by the app's), and WebKit's GPU process for Safari.
    static func tapTargets(pid: pid_t, bundleIdentifier: String?) -> [AudioObjectID] {
        var targets: [AudioObjectID] = []
        if let object = processObject(for: pid) { targets.append(object) }
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return targets }
        for object in processObjects() where !targets.contains(object) {
            guard let processBundle = string(object, processBundleID) else { continue }
            if processBundle.hasPrefix(bundleIdentifier + ".")
                || (bundleIdentifier == NowPlayingBundleID.safari && processBundle == NowPlayingBundleID.webKitGPU) {
                targets.append(object)
            }
        }
        return targets
    }
}

// MARK: - Analyzer

/// Mixes the tap to mono, runs a Hann-windowed FFT at 20 Hz and reports one
/// 0…1 level per band (edges 20·81·170·527·1500·4500·10000 Hz, Part F §1).
/// Runs entirely on the tap's IO queue.
final class NowPlayingSpectrumAnalyzer {
    private let fftSize = NowPlayingMetrics.Live.fftSize
    private let log2n: vDSP_Length
    private let setup: FFTSetup?
    private var window: [Float]
    private var ring: [Float]
    private var linear: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]
    private var writeIndex = 0
    private var samplesSinceEmit = 0
    private var hop = 2400
    private var bandBins: [(Int, Int)] = []
    private var sampleRate: Double = 0
    private let onLevels: @Sendable ([Float]) -> Void

    init(onLevels: @escaping @Sendable ([Float]) -> Void) {
        self.onLevels = onLevels
        let n = NowPlayingMetrics.Live.fftSize
        let exponent = vDSP_Length(log2(Double(n)))
        log2n = exponent
        setup = vDSP_create_fftsetup(exponent, FFTRadix(kFFTRadix2))
        var hann = [Float](repeating: 0, count: n)
        vDSP_hann_window(&hann, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        window = hann
        ring = [Float](repeating: 0, count: n)
        linear = [Float](repeating: 0, count: n)
        windowed = [Float](repeating: 0, count: n)
        real = [Float](repeating: 0, count: n / 2)
        imag = [Float](repeating: 0, count: n / 2)
        magnitudes = [Float](repeating: 0, count: n / 2)
    }

    deinit {
        if let setup { vDSP_destroy_fftsetup(setup) }
    }

    func configure(sampleRate: Double) {
        guard sampleRate > 0, sampleRate != self.sampleRate else { return }
        self.sampleRate = sampleRate
        hop = max(256, Int(sampleRate / Constants.Waveform.liveRefreshHz))
        let edges = Constants.Waveform.liveBandEdges
        let binWidth = sampleRate / Double(fftSize)
        bandBins = (0..<(edges.count - 1)).map { index in
            let low = max(1, Int((edges[index] / binWidth).rounded(.down)))
            let high = min(fftSize / 2 - 1, max(low, Int((edges[index + 1] / binWidth).rounded(.up)) - 1))
            return (low, high)
        }
    }

    /// Consumes one IO buffer list of Float32 samples.
    func process(_ bufferList: UnsafePointer<AudioBufferList>, interleavedChannels: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard buffers.count > 0 else { return }

        if buffers.count == 1 {
            // Interleaved (or mono): average the channels of each frame.
            let buffer = buffers[0]
            let channels = max(1, Int(buffer.mNumberChannels))
            guard let data = buffer.mData else { return }
            let samples = data.assumingMemoryBound(to: Float.self)
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            let scale = 1 / Float(channels)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels { sum += samples[frame * channels + channel] }
                push(sum * scale)
            }
        } else {
            // Non-interleaved: one buffer per channel.
            var frames = Int.max
            for buffer in buffers {
                frames = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
            }
            guard frames != Int.max, frames > 0 else { return }
            let scale = 1 / Float(buffers.count)
            for frame in 0..<frames {
                var sum: Float = 0
                for buffer in buffers {
                    if let data = buffer.mData {
                        sum += data.assumingMemoryBound(to: Float.self)[frame]
                    }
                }
                push(sum * scale)
            }
        }
    }

    private func push(_ sample: Float) {
        ring[writeIndex] = sample
        writeIndex = (writeIndex + 1) % fftSize
        samplesSinceEmit += 1
        if samplesSinceEmit >= hop {
            samplesSinceEmit = 0
            analyze()
        }
    }

    private func analyze() {
        guard let setup, !bandBins.isEmpty else { return }
        let n = fftSize
        let half = n / 2

        // Unroll the ring buffer, oldest sample first.
        let tail = n - writeIndex
        for i in 0..<tail { linear[i] = ring[writeIndex + i] }
        for i in 0..<writeIndex { linear[tail + i] = ring[i] }
        vDSP_vmul(linear, 1, window, 1, &windowed, 1, vDSP_Length(n))

        real.withUnsafeMutableBufferPointer { realBuffer in
            imag.withUnsafeMutableBufferPointer { imagBuffer in
                guard let realBase = realBuffer.baseAddress, let imagBase = imagBuffer.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                windowed.withUnsafeBufferPointer { input in
                    guard let inputBase = input.baseAddress else { return }
                    inputBase.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                magnitudes.withUnsafeMutableBufferPointer { magnitudeBuffer in
                    guard let magnitudeBase = magnitudeBuffer.baseAddress else { return }
                    vDSP_zvmags(&split, 1, magnitudeBase, 1, vDSP_Length(half))
                }
            }
        }
        magnitudes[0] = 0 // DC (imag[0] carries Nyquist)

        // Band amplitude ≈ a sine's amplitude (zrip ×2, Hann gain ½, ENBW 1.5).
        let normalisation = Float(n / 2) * Float(1.5).squareRoot()
        let floorDB = NowPlayingMetrics.Live.floorDB
        let range = NowPlayingMetrics.Live.ceilingDB - floorDB
        var levels: [Float] = []
        levels.reserveCapacity(bandBins.count)
        for (low, high) in bandBins {
            var sum: Float = 0
            if high >= low {
                for bin in low...high { sum += magnitudes[bin] }
            }
            let amplitude = sum.squareRoot() / normalisation
            let db = 20 * log10(max(amplitude, 1e-9))
            levels.append(min(max((db - floorDB) / range, 0), 1))
        }
        onLevels(levels)
    }
}

// MARK: - Process tap

/// A Core Audio process tap on the now-playing app, wrapped in a private
/// aggregate device whose IOProc feeds the analyzer (teardown §7.5 recipe:
/// CATapDescription → AudioHardwareCreateProcessTap → aggregate device with
/// a tap list → IOProc → FFT → bands).
final class NowPlayingProcessTap {
    enum TapError: Error { case noProcess, tapFailed(OSStatus), noFormat, aggregateFailed(OSStatus), ioProcFailed(OSStatus) }

    private let queue = DispatchQueue(label: "app.foyer.nowplaying.processtap", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let analyzer: NowPlayingSpectrumAnalyzer
    let pid: pid_t

    init(pid: pid_t, onLevels: @escaping @Sendable ([Float]) -> Void) {
        self.pid = pid
        analyzer = NowPlayingSpectrumAnalyzer(onLevels: onLevels)
    }

    deinit {
        stop()
    }

    func start(bundleIdentifier: String?) throws {
        let targets = NowPlayingCoreAudio.tapTargets(pid: pid, bundleIdentifier: bundleIdentifier)
        guard !targets.isEmpty else { throw TapError.noProcess }

        let description = CATapDescription(stereoMixdownOfProcesses: targets)
        var newTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTap)
        guard tapStatus == noErr, newTap != AudioObjectID(kAudioObjectUnknown) else { throw TapError.tapFailed(tapStatus) }
        tapID = newTap

        guard let tapUID = NowPlayingCoreAudio.string(tapID, NowPlayingCoreAudio.tapUIDSelector),
              let format = NowPlayingCoreAudio.tapFormat(tapID) else {
            stop()
            throw TapError.noFormat
        }
        analyzer.configure(sampleRate: format.mSampleRate)
        let channels = Int(max(1, format.mChannelsPerFrame))

        var aggregate: [String: Any] = [
            "name": "Foyer Waveform Tap",
            "uid": "app.foyer.waveform.\(UUID().uuidString)",
            "private": true,
            "stacked": false,
            "tapautostart": true,
            "taps": [["uid": tapUID, "drift": true]],
        ]
        if let output = NowPlayingCoreAudio.defaultOutputDevice(),
           let outputUID = NowPlayingCoreAudio.string(output, kAudioDevicePropertyDeviceUID) {
            aggregate["master"] = outputUID
            aggregate["subdevices"] = [["uid": outputUID]]
        }

        var newAggregate = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &newAggregate)
        guard aggregateStatus == noErr else {
            stop()
            throw TapError.aggregateFailed(aggregateStatus)
        }
        aggregateID = newAggregate

        let analyzer = self.analyzer
        let block: AudioDeviceIOBlock = { _, inputData, _, _, _ in
            analyzer.process(inputData, interleavedChannels: channels)
        }
        var newProc: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&newProc, aggregateID, queue, block)
        guard procStatus == noErr, let newProc else {
            stop()
            throw TapError.ioProcFailed(procStatus)
        }
        procID = newProc
        let startStatus = AudioDeviceStart(aggregateID, newProc)
        guard startStatus == noErr else {
            stop()
            throw TapError.ioProcFailed(startStatus)
        }
    }

    func stop() {
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }
}

// MARK: - Shared hub

/// One tap shared by every live waveform on screen (compact, expanded,
/// Duo, lock screen): views `acquire`/`release` ownership and the tap runs
/// only while someone owns it, live waveform is on, permission is granted and
/// the source is playing (Alcove's `WaveformSpectrumCenter`/`activeSpectrumOwners`).
@MainActor
final class NowPlayingSpectrumCenter: ObservableObject {
    static let shared = NowPlayingSpectrumCenter()

    /// Six band levels, 0…1, low frequencies first.
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: Constants.Waveform.liveBandCount)
    /// True while a tap is delivering levels.
    @Published private(set) var isLive = false
    @Published private(set) var permission: NowPlayingAudioCapturePermission.Status = .unknown

    private var owners = Set<UUID>()
    private var tap: NowPlayingProcessTap?
    private var tapBundle: String?
    private var stopTask: Task<Void, Never>?
    private var failedPID: pid_t?
    private var cancellables = Set<AnyCancellable>()
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var isRequestingPermission = false

    private init() {
        permission = NowPlayingAudioCapturePermission.preflight()

        Defaults.publisher(.useLiveWaveform, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.failedPID = nil
                self?.reevaluate()
            }
            .store(in: &cancellables)

        // Re-create the aggregate when the output device changes.
        var address = NowPlayingCoreAudio.propertyAddress(kAudioHardwarePropertyDefaultSystemOutputDevice)
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in NowPlayingSpectrumCenter.shared.restartTap() }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address,
                                               DispatchQueue.main, listener) == noErr {
            deviceListener = listener
        }
    }

    /// Five-band variant used by the compact glyph (the 20–81 and 81–170 Hz
    /// bands merged into 20–170 Hz).
    var compactLevels: [CGFloat] {
        guard levels.count >= 6 else { return levels }
        return [max(levels[0], levels[1])] + Array(levels[2...])
    }

    func acquire(_ owner: UUID) {
        owners.insert(owner)
        reevaluate()
    }

    func release(_ owner: UUID) {
        owners.remove(owner)
        reevaluate()
    }

    /// The crossed-mic "unblock" action in Settings.
    func requestPermission() {
        NowPlayingAudioCapturePermission.request { [weak self] granted in
            guard let self else { return }
            self.permission = granted ? .granted : NowPlayingAudioCapturePermission.preflight()
            self.failedPID = nil
            self.reevaluate()
        }
    }

    func refreshPermission() {
        permission = NowPlayingAudioCapturePermission.preflight()
        reevaluate()
    }

    func reevaluate() {
        let manager = NowPlayingManager.shared
        let pid = manager.snapshot?.processIdentifier
        let wantsTap = !owners.isEmpty && Defaults[.useLiveWaveform] && manager.isPlaying && pid != nil

        guard wantsTap, let pid else {
            scheduleStop()
            return
        }
        stopTask?.cancel()
        stopTask = nil

        if permission != .granted {
            permission = NowPlayingAudioCapturePermission.preflight()
        }
        switch permission {
        case .granted, .unknown:
            break
        case .notDetermined:
            // Ask once; the tap itself also triggers the system prompt.
            if !Defaults[.hasPromptedAudioPermission], !isRequestingPermission {
                isRequestingPermission = true
                NowPlayingAudioCapturePermission.request { [weak self] granted in
                    guard let self else { return }
                    self.isRequestingPermission = false
                    self.permission = granted ? .granted : .denied
                    self.reevaluate()
                }
            }
            return
        case .denied:
            stopTap()
            return
        }

        if let tap, tap.pid == pid { return }
        guard failedPID != pid else { return }
        startTap(pid: pid, bundleIdentifier: manager.snapshot?.sourceAppBundleIdentifier)
    }

    private func startTap(pid: pid_t, bundleIdentifier: String?) {
        stopTap()
        let newTap = NowPlayingProcessTap(pid: pid) { levels in
            let values = levels.map { CGFloat($0) }
            Task { @MainActor in NowPlayingSpectrumCenter.shared.receive(values) }
        }
        do {
            try newTap.start(bundleIdentifier: bundleIdentifier)
            tap = newTap
            tapBundle = bundleIdentifier
            isLive = true
        } catch {
            failedPID = pid
            isLive = false
        }
    }

    private func receive(_ values: [CGFloat]) {
        guard tap != nil else { return }
        levels = values
    }

    private func restartTap() {
        guard let tap else { return }
        let pid = tap.pid
        let bundle = tapBundle
        startTap(pid: pid, bundleIdentifier: bundle)
    }

    private func scheduleStop() {
        guard tap != nil, stopTask == nil else { return }
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NowPlayingMetrics.Live.teardownGrace))
            guard let self, !Task.isCancelled else { return }
            self.stopTask = nil
            self.stopTap()
        }
    }

    private func stopTap() {
        tap?.stop()
        tap = nil
        tapBundle = nil
        isLive = false
        levels = Array(repeating: 0, count: Constants.Waveform.liveBandCount)
    }
}
