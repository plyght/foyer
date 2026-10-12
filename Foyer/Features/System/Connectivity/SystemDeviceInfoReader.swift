import CoreAudio
import Foundation
import IOBluetooth
import IOKit

/// What system_profiler / the HID registry know about a device.
struct SystemExternalDeviceInfo: Equatable {
    var name: String?
    var productID: String?
    var minorType: String?
    var battery = SystemDeviceBattery()
}

/// Best-effort readers for device model and battery (Part E §3).
enum SystemDeviceInfoReader {

    // MARK: IOBluetoothDevice private selectors (main thread)

    /// `batteryPercentLeft` / `Right` / `Case` / `Single` via KVC, guarded by
    /// `responds(to:)` so a missing selector never raises.
    static func bluetoothBattery(_ device: IOBluetoothDevice) -> SystemDeviceBattery {
        SystemDeviceBattery(left: SystemDeviceBattery.valid(integer(device, "batteryPercentLeft")),
                            right: SystemDeviceBattery.valid(integer(device, "batteryPercentRight")),
                            caseLevel: SystemDeviceBattery.valid(integer(device, "batteryPercentCase")),
                            single: SystemDeviceBattery.valid(integer(device, "batteryPercentSingle")))
    }

    /// Bluetooth product id as four lower-case hex digits (e.g. "2014").
    static func bluetoothProductID(_ device: IOBluetoothDevice) -> String? {
        guard let value = integer(device, "productID"), value > 0 else { return nil }
        var hex = String(value, radix: 16)
        while hex.count < 4 { hex = "0" + hex }
        return hex
    }

    /// Private `colorID` (AirPods Max colour).
    static func bluetoothColorID(_ device: IOBluetoothDevice) -> Int? {
        integer(device, "colorID")
    }

    private static func integer(_ object: NSObject, _ key: String) -> Int? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        if let number = object.value(forKey: key) as? NSNumber { return number.intValue }
        return nil
    }

    // MARK: CoreAudio model UID ('muid', global scope)

    /// The first space-separated component of the model UID of the
    /// Bluetooth audio device with `address` (Alcove's classifier source).
    static func coreAudioModelIdentifier(forAddress address: String) -> String? {
        for deviceID in audioDeviceIDs() {
            guard let uid = stringProperty(deviceID, kAudioDevicePropertyDeviceUID),
                  SystemBluetoothAddress.normalize(uid) == address,
                  let model = stringProperty(deviceID, kAudioDevicePropertyModelUID),
                  let first = model.split(separator: " ").first else { continue }
            return String(first).lowercased()
        }
        return nil
    }

    private static func audioDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        let status = ids.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return -1 }
            return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, base)
        }
        return status == noErr ? ids : []
    }

    private static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) { pointer -> OSStatus in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let unmanaged = value else { return nil }
        return unmanaged.takeRetainedValue() as String
    }

    // MARK: HID registry (Magic Keyboard / Mouse / Trackpad), any thread

    /// `BatteryPercent` of every `AppleDeviceManagementHIDEventService`,
    /// keyed by normalised address.
    static func hidBatteryLevels() -> [String: Int] {
        var result: [String: Int] = [:]
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return result }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let percent = registryProperty(service, "BatteryPercent") as? NSNumber
            let address = registryProperty(service, "DeviceAddress") as? String
            if let percent, let key = SystemBluetoothAddress.normalize(address),
               let valid = SystemDeviceBattery.valid(percent.intValue) {
                result[key] = valid
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }

    private static func registryProperty(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    // MARK: system_profiler (background only)

    /// Runs `system_profiler SPBluetoothDataType -json` and returns the
    /// connected devices keyed by normalised address. Blocking; call off the
    /// main thread.
    static func systemProfilerDevices() -> [String: SystemExternalDeviceInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return [:]
        }
        let watchdog = DispatchWorkItem { [process] in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility)
            .asyncAfter(deadline: .now() + SystemConstants.Connectivity.profilerTimeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return parseSystemProfiler(data)
    }

    static func parseSystemProfiler(_ data: Data) -> [String: SystemExternalDeviceInfo] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [:] }
        var result: [String: SystemExternalDeviceInfo] = [:]
        for controller in controllers {
            guard let connected = controller["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    guard let fields = value as? [String: Any],
                          let key = SystemBluetoothAddress.normalize(fields["device_address"] as? String)
                    else { continue }
                    var info = SystemExternalDeviceInfo()
                    info.name = name
                    info.productID = fields["device_productID"] as? String
                    info.minorType = fields["device_minorType"] as? String
                    info.battery = SystemDeviceBattery(
                        left: percent(fields["device_batteryLevelLeft"]),
                        right: percent(fields["device_batteryLevelRight"]),
                        caseLevel: percent(fields["device_batteryLevelCase"]),
                        single: percent(fields["device_batteryLevelMain"]) ?? percent(fields["device_batteryLevel"]))
                    result[key] = info
                }
            }
        }
        return result
    }

    private static func percent(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return SystemDeviceBattery.valid(number.intValue) }
        guard let string = value as? String else { return nil }
        let digits = string.filter { $0.isNumber }
        return SystemDeviceBattery.valid(Int(digits))
    }
}
