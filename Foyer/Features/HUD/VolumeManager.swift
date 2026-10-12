import AppKit
import AudioToolbox
import Combine
import CoreAudio
import Foundation
import IOKit.ps

/// What the default output device is, used for the HUD's leading glyph when
/// "Show device" is selected (Part C2 §1.6, Part E §3).
enum VolumeOutputDeviceKind: Equatable {
    case builtInSpeakers
    case builtInHeadphones
    case airPods
    case airPodsGen3
    case airPodsGen4
    case airPodsPro
    case airPodsMax
    case beats
    case bluetoothHeadphones
    case bluetoothSpeaker
    case homePod
    case airPlay
    case display
    case usb
    case other
}

/// The default output device's volume, mute state and identity, read and
/// written with raw CoreAudio. Alcove uses SimplyCoreAudio for the same job
/// (Part A §2); Foyer talks to the HAL directly.
///
/// Programmatic volume changes (AppleScript, Control Center) update the
/// published values but never show a HUD: Alcove only shows the Sound HUD for
/// key-driven changes (Part C §3.2).
@MainActor
final class VolumeManager: ObservableObject {
    static let shared = VolumeManager()

    /// Output volume, 0…1.
    @Published private(set) var volume: Float = 0
    @Published private(set) var isMuted: Bool = false
    @Published private(set) var outputDeviceName: String = ""
    /// `kAudioDevicePropertyTransportType` of the default output device.
    @Published private(set) var outputDeviceTransport: UInt32 = 0
    @Published private(set) var outputDeviceKind: VolumeOutputDeviceKind = .other
    /// False when the device has no settable volume (e.g. some HDMI/optical
    /// outputs). Keys then pass through to macOS.
    @Published private(set) var isAdjustable: Bool = false
    @Published private(set) var canMute: Bool = false

    private var deviceID = AudioDeviceID(kAudioObjectUnknown)
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var isStarted = false
    /// Software mute for devices without a mute control.
    private var emulatedMute = false
    private var volumeBeforeEmulatedMute: Float = 0

    private init() {
        refreshDevice()
    }

    // MARK: Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated {
                VolumeManager.shared.defaultDeviceChanged()
            }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block) == noErr {
            systemListener = block
        }
        refreshDevice()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        removeDeviceListeners()
        if let block = systemListener {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
            systemListener = nil
        }
    }

    // MARK: Public API

    /// Sets the output volume (0…1). A non-zero value clears mute, like the
    /// system volume slider.
    func setVolume(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        if emulatedMute {
            emulatedMute = false
            isMuted = false
        }
        writeVolume(clamped)
        volume = clamped
        if clamped > 0, isMuted {
            writeMute(false)
            isMuted = false
        }
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        if canMute {
            writeMute(muted)
            isMuted = muted
            return
        }
        // No hardware mute: emulate it with the volume.
        guard isAdjustable else { return }
        if muted {
            volumeBeforeEmulatedMute = volume
            emulatedMute = true
            writeVolume(0)
            isMuted = true
        } else {
            emulatedMute = false
            let restored = volumeBeforeEmulatedMute > 0 ? volumeBeforeEmulatedMute : HUDConstants.normalStep
            writeVolume(restored)
            volume = restored
            isMuted = false
        }
    }

    /// One media-key step: ±1/16, or ±1/64 when `fine`. The value is snapped
    /// to the step grid like the system does. Any step unmutes.
    func step(up: Bool, fine: Bool) {
        let step = HUDConstants.normalStep * (fine ? HUDConstants.fineStepScale : 1)
        let base: Float
        if emulatedMute {
            base = 0
        } else {
            base = volume
        }
        let index = (base / step).rounded()
        var target = (index + (up ? 1 : -1)) * step
        target = min(max(target, 0), 1)
        if isMuted {
            setMuted(false)
        }
        writeVolume(target)
        volume = target
    }

    /// Volume to draw (0 while muted).
    var displayedLevel: Float { isMuted ? 0 : volume }

    // MARK: Device

    private func defaultDeviceChanged() {
        emulatedMute = false
        refreshDevice()
    }

    private func refreshDevice() {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        let newID = status == noErr ? id : AudioDeviceID(kAudioObjectUnknown)

        if newID != deviceID || deviceListeners.isEmpty {
            removeDeviceListeners()
            deviceID = newID
            if isStarted { installDeviceListeners() }
        }
        readDeviceIdentity()
        readVolumeAndMute()
    }

    private func readDeviceIdentity() {
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            outputDeviceName = ""
            outputDeviceTransport = 0
            outputDeviceKind = .other
            isAdjustable = false
            canMute = false
            return
        }
        let name = Self.stringProperty(deviceID, kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal) ?? ""
        let transport = Self.uint32Property(deviceID, kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal) ?? 0
        let model = Self.stringProperty(deviceID, kAudioDevicePropertyModelUID, scope: kAudioObjectPropertyScopeGlobal) ?? ""
        let dataSource = Self.uint32Property(deviceID, kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput)

        outputDeviceName = name
        outputDeviceTransport = transport
        outputDeviceKind = Self.classify(name: name, transport: transport, modelUID: model, dataSource: dataSource)
        isAdjustable = volumeIsSettable()
        canMute = muteIsSettable()
    }

    private func readVolumeAndMute() {
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return }
        if let v = readVolume() {
            if !emulatedMute { volume = v }
        }
        if canMute {
            isMuted = readMute() ?? false
        } else {
            isMuted = emulatedMute
        }
    }

    private func installDeviceListeners() {
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return }
        let output = kAudioDevicePropertyScopeOutput
        let main = kAudioObjectPropertyElementMain
        let addresses: [AudioObjectPropertyAddress] = [
            Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: output),
            Self.address(kAudioDevicePropertyVolumeScalar, scope: output, element: main),
            Self.address(kAudioDevicePropertyVolumeScalar, scope: output, element: 1),
            Self.address(kAudioDevicePropertyVolumeScalar, scope: output, element: 2),
            Self.address(kAudioDevicePropertyMute, scope: output, element: main),
            Self.address(kAudioDevicePropertyMute, scope: output, element: 1),
            Self.address(kAudioDevicePropertyDataSource, scope: output),
            Self.address(kAudioObjectPropertyName),
        ]
        for addr in addresses {
            var a = addr
            guard AudioObjectHasProperty(deviceID, &a) else { continue }
            let isIdentity = addr.mSelector == kAudioDevicePropertyDataSource || addr.mSelector == kAudioObjectPropertyName
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                MainActor.assumeIsolated {
                    let manager = VolumeManager.shared
                    if isIdentity { manager.readDeviceIdentity() }
                    manager.readVolumeAndMute()
                }
            }
            if AudioObjectAddPropertyListenerBlock(deviceID, &a, DispatchQueue.main, block) == noErr {
                deviceListeners.append((addr, block))
            }
        }
    }

    private func removeDeviceListeners() {
        for (addr, block) in deviceListeners {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(deviceID, &a, DispatchQueue.main, block)
        }
        deviceListeners.removeAll()
    }

    // MARK: Volume I/O

    private var outputChannels: [AudioObjectPropertyElement] { [1, 2] }

    private func volumeIsSettable() -> Bool {
        let output = kAudioDevicePropertyScopeOutput
        if Self.isSettable(deviceID, Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: output)) { return true }
        if Self.isSettable(deviceID, Self.address(kAudioDevicePropertyVolumeScalar, scope: output, element: kAudioObjectPropertyElementMain)) { return true }
        for channel in outputChannels where Self.isSettable(deviceID, Self.address(kAudioDevicePropertyVolumeScalar, scope: output, element: channel)) {
            return true
        }
        return false
    }

    private func muteIsSettable() -> Bool {
        let output = kAudioDevicePropertyScopeOutput
        if Self.isSettable(deviceID, Self.address(kAudioDevicePropertyMute, scope: output, element: kAudioObjectPropertyElementMain)) { return true }
        for channel in outputChannels where Self.isSettable(deviceID, Self.address(kAudioDevicePropertyMute, scope: output, element: channel)) {
            return true
        }
        return false
    }

    private func readVolume() -> Float? {
        let output = kAudioDevicePropertyScopeOutput
        if let v = Self.floatProperty(deviceID, Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: output)) {
            return min(max(v, 0), 1)
        }
        if let v = Self.floatProperty(deviceID, Self.address(kAudioDevicePropertyVolumeScalar, scope: output, element: kAudioObjectPropertyElementMain)) {
            return min(max(v, 0), 1)
        }
        var values: [Float] = []
        for channel in outputChannels {
            if let v = Self.floatProperty(deviceID, Self.address(kAudioDevicePropertyVolumeScalar, scope: output, element: channel)) {
                values.append(v)
            }
        }
        guard !values.isEmpty else { return nil }
        let average = values.reduce(0, +) / Float(values.count)
        return min(max(average, 0), 1)
    }

    private func writeVolume(_ value: Float) {
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return }
        let output = kAudioDevicePropertyScopeOutput
        let virtualMain = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: output)
        if Self.isSettable(deviceID, virtualMain), Self.setFloat(deviceID, virtualMain, value) { return }
        let mainScalar = Self.address(kAudioDevicePropertyVolumeScalar, scope: output, element: kAudioObjectPropertyElementMain)
        if Self.isSettable(deviceID, mainScalar), Self.setFloat(deviceID, mainScalar, value) { return }
        for channel in outputChannels {
            let addr = Self.address(kAudioDevicePropertyVolumeScalar, scope: output, element: channel)
            if Self.isSettable(deviceID, addr) {
                _ = Self.setFloat(deviceID, addr, value)
            }
        }
    }

    private func readMute() -> Bool? {
        let output = kAudioDevicePropertyScopeOutput
        if let m = Self.uint32Property(deviceID, kAudioDevicePropertyMute, scope: output, element: kAudioObjectPropertyElementMain) {
            return m != 0
        }
        for channel in outputChannels {
            if let m = Self.uint32Property(deviceID, kAudioDevicePropertyMute, scope: output, element: channel) {
                return m != 0
            }
        }
        return nil
    }

    private func writeMute(_ muted: Bool) {
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return }
        let output = kAudioDevicePropertyScopeOutput
        let main = Self.address(kAudioDevicePropertyMute, scope: output, element: kAudioObjectPropertyElementMain)
        if Self.isSettable(deviceID, main), Self.setUInt32(deviceID, main, muted ? 1 : 0) { return }
        for channel in outputChannels {
            let addr = Self.address(kAudioDevicePropertyMute, scope: output, element: channel)
            if Self.isSettable(deviceID, addr) {
                _ = Self.setUInt32(deviceID, addr, muted ? 1 : 0)
            }
        }
    }

    // MARK: Classification (Part E §3)

    /// Model UID first component → AirPods family (fn 0x10031a2c4).
    private static func classify(name: String, transport: UInt32, modelUID: String, dataSource: UInt32?) -> VolumeOutputDeviceKind {
        let lowerName = name.lowercased()
        let modelKey = modelUID.split(separator: " ").first.map { String($0).lowercased() } ?? ""

        switch modelKey {
        case "2002", "200f": return .airPods
        case "2013": return .airPodsGen3
        case "201b", "2019": return .airPodsGen4
        case "200e", "2014", "2024", "2027": return .airPodsPro
        case "200a", "201f", "202d": return .airPodsMax
        default: break
        }

        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            // 'hdpn' = headphones jack, 'ispk' = internal speakers.
            if dataSource == 0x6864_706E { return .builtInHeadphones }
            return .builtInSpeakers
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            if lowerName.contains("airpods max") { return .airPodsMax }
            if lowerName.contains("airpods pro") { return .airPodsPro }
            if lowerName.contains("airpods") { return .airPods }
            if lowerName.contains("beats") || lowerName.contains("powerbeats") { return .beats }
            if lowerName.contains("homepod") { return .homePod }
            if lowerName.contains("speaker") || lowerName.contains("boom") || lowerName.contains("soundlink") {
                return .bluetoothSpeaker
            }
            return .bluetoothHeadphones
        case kAudioDeviceTransportTypeAirPlay:
            return lowerName.contains("homepod") ? .homePod : .airPlay
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return .display
        case kAudioDeviceTransportTypeUSB:
            if lowerName.contains("display") { return .display }
            return .usb
        case kAudioDeviceTransportTypeThunderbolt:
            return lowerName.contains("display") ? .display : .usb
        default:
            if lowerName.contains("homepod") { return .homePod }
            return .other
        }
    }

    // MARK: CoreAudio helpers

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var a = address
        guard AudioObjectHasProperty(object, &a) else { return false }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(object, &a, &settable) == noErr else { return false }
        return settable.boolValue
    }

    private static func floatProperty(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Float? {
        var a = address
        guard AudioObjectHasProperty(object, &a) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &size, &value) == noErr else { return nil }
        return Float(value)
    }

    private static func setFloat(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: Float) -> Bool {
        var a = address
        var v = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(object, &a, 0, nil, size, &v) == noErr
    }

    private static func uint32Property(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                       scope: AudioObjectPropertyScope,
                                       element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> UInt32? {
        var a = address(selector, scope: scope, element: element)
        guard AudioObjectHasProperty(object, &a) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func setUInt32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: UInt32) -> Bool {
        var a = address
        var v = value
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(object, &a, 0, nil, size, &v) == noErr
    }

    private static func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                       scope: AudioObjectPropertyScope) -> String? {
        var a = address(selector, scope: scope)
        guard AudioObjectHasProperty(object, &a) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(object, &a, 0, nil, &size, ptr)
        }
        guard status == noErr, let string = value?.takeRetainedValue() else { return nil }
        return string as String
    }

    // MARK: Host shape (for the built-in speaker glyph)

    /// True on Macs with an internal battery (laptops).
    static let hostIsLaptop: Bool = {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let type = description[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType { return true }
        }
        return false
    }()
}
