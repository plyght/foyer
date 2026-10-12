import AppKit
import Combine
import CoreBluetooth
import Defaults
import IOBluetooth
import SwiftUI

enum SystemConnectivityEventKind: Equatable {
    case connected, disconnected, lowBattery
}

/// One connectivity notification. Views look the device up by id so model
/// and battery updates that arrive after posting show live.
struct SystemConnectivityEvent: Identifiable, Equatable {
    let id = UUID()
    var kind: SystemConnectivityEventKind
    var device: SystemConnectedDevice
}

/// Alcove's `ConnectivityManager` (Part E §3): Bluetooth connect /
/// disconnect, AirPods model and colour, battery levels and the
/// low-battery warning for connected devices.
@MainActor
final class SystemConnectivityManager: ObservableObject {
    static let shared = SystemConnectivityManager()

    /// Connected devices, oldest first.
    @Published private(set) var devices: [SystemConnectedDevice] = []
    @Published private(set) var currentEvent: SystemConnectivityEvent?
    @Published private(set) var authorization: CBManagerAuthorization = CBManager.authorization
    @Published private(set) var isMonitoring = false

    private struct Announcement {
        var kind: SystemConnectivityEventKind
        var date: Date
    }

    private let target = SystemBluetoothNotificationTarget()
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var bluetoothDevices: [String: IOBluetoothDevice] = [:]
    private var centralManager: CBCentralManager?
    private let centralDelegate = SystemBluetoothAuthorizationDelegate()
    private var suppressUntil: Date = .distantPast
    private var lowLatched: Set<String> = []
    private var lastAnnounced: [String: Announcement] = [:]
    private var pendingPresentations: [String: Task<Void, Never>] = [:]
    private var enrichmentTasks: [String: Task<Void, Never>] = [:]
    private var pollTimer: Timer?
    private var lastProfilerRun: Date = .distantPast
    private var backgroundRefreshInFlight = false
    private var externalInfo: [String: SystemExternalDeviceInfo] = [:]
    private var hidLevels: [String: Int] = [:]
    private var defaultsObservers: [Defaults.Observation] = []
    private var isStarted = false

    private init() {}

    func device(_ id: String) -> SystemConnectedDevice? {
        devices.first { $0.id == id }
    }

    // MARK: Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true

        defaultsObservers.append(Defaults.observe(.enableConnectivity, options: []) { _ in
            Task { @MainActor in SystemConnectivityManager.shared.enabledChanged() }
        })
        defaultsObservers.append(Defaults.observe(.lowConnectBatteryThreshold, options: []) { _ in
            Task { @MainActor in SystemConnectivityManager.shared.rearmLowBattery() }
        })

        enabledChanged()
    }

    private func enabledChanged() {
        if Defaults[.enableConnectivity] {
            ensureMonitoring()
        } else {
            stopMonitoring()
        }
    }

    private func ensureMonitoring() {
        let status = CBManager.authorization
        if authorization != status { authorization = status }
        switch status {
        case .allowedAlways:
            beginMonitoring()
        case .notDetermined:
            // Ask once; onboarding asks on first launch, later launches don't nag.
            if !Defaults[.isFirstLaunch], !Defaults[.hasPromptedBluetoothPermission] {
                requestBluetoothPermission()
            }
        default:
            break
        }
    }

    /// Creates a `CBCentralManager`, which makes macOS show the Bluetooth
    /// prompt when the decision is still pending.
    func requestBluetoothPermission() {
        Defaults[.hasPromptedBluetoothPermission] = true
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: centralDelegate, queue: nil,
                                          options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    fileprivate func authorizationChanged() {
        let status = CBManager.authorization
        if authorization != status { authorization = status }
        if status == .allowedAlways, Defaults[.enableConnectivity] {
            beginMonitoring()
        }
    }

    private func beginMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        suppressUntil = Date().addingTimeInterval(SystemConstants.Connectivity.initialSuppression)

        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: target,
            selector: #selector(SystemBluetoothNotificationTarget.deviceConnected(_:device:)))

        if let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for device in paired where device.isConnected() {
                handleConnected(device)
            }
        }

        let timer = Timer(timeInterval: SystemConstants.Connectivity.batteryPoll, repeats: true) { _ in
            SystemMainThread.run { SystemConnectivityManager.shared.poll() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        bluetoothDevices.removeAll()
        pendingPresentations.values.forEach { $0.cancel() }
        pendingPresentations.removeAll()
        enrichmentTasks.values.forEach { $0.cancel() }
        enrichmentTasks.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        lowLatched.removeAll()
        devices.removeAll()
        if currentEvent != nil { currentEvent = nil }
        NotchController.shared.dismissNotification(.connectivity)
    }

    // MARK: IOBluetooth callbacks

    fileprivate func handleConnected(_ device: IOBluetoothDevice) {
        guard isMonitoring, let address = SystemBluetoothAddress.normalize(device.addressString) else { return }

        if disconnectNotifications[address] == nil,
           let note = device.register(
            forDisconnectNotification: target,
            selector: #selector(SystemBluetoothNotificationTarget.deviceDisconnected(_:device:))) {
            disconnectNotifications[address] = note
        }
        bluetoothDevices[address] = device

        let snapshot = makeSnapshot(device, address: address, connectedAt: Date())
        if let index = devices.firstIndex(where: { $0.id == address }) {
            var updated = snapshot
            updated.connectedAt = devices[index].connectedAt
            devices[index] = updated
            return
        }
        devices.append(snapshot)
        scheduleEnrichment(address)

        guard Date() >= suppressUntil else {
            // Already connected at launch: latch silently.
            if isLow(snapshot) { lowLatched.insert(address) }
            return
        }

        pendingPresentations[address]?.cancel()
        pendingPresentations[address] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(SystemConstants.Connectivity.presentDelay))
            guard !Task.isCancelled else { return }
            SystemConnectivityManager.shared.announceConnected(address)
        }
    }

    fileprivate func handleDisconnected(_ device: IOBluetoothDevice) {
        guard let address = SystemBluetoothAddress.normalize(device.addressString) else { return }
        let wasPending = pendingPresentations[address] != nil
        pendingPresentations.removeValue(forKey: address)?.cancel()
        enrichmentTasks.removeValue(forKey: address)?.cancel()
        disconnectNotifications.removeValue(forKey: address)?.unregister()
        bluetoothDevices[address] = nil
        lowLatched.remove(address)

        guard let index = devices.firstIndex(where: { $0.id == address }) else { return }
        let snapshot = devices.remove(at: index)

        // A connection that was never announced is not announced as lost either.
        guard isMonitoring, !wasPending, Date() >= suppressUntil, !isFlapping(address, .disconnected) else { return }
        present(.disconnected, device: snapshot)
    }

    private func announceConnected(_ address: String) {
        pendingPresentations[address] = nil
        refreshDevice(address)
        guard let device = device(address) else { return }
        if !isFlapping(address, .connected) {
            present(.connected, device: device)
        }
        if isLow(device), !lowLatched.contains(address) {
            lowLatched.insert(address)
            if Defaults[.warnOnLowConnectBattery], Defaults[.playSoundOnLowConnectBattery] {
                SoundPlayer.play(.lowBattery)
            }
        }
    }

    private func isFlapping(_ address: String, _ kind: SystemConnectivityEventKind) -> Bool {
        guard let last = lastAnnounced[address], last.kind == kind else { return false }
        return Date().timeIntervalSince(last.date) < SystemConstants.Connectivity.flapWindow
    }

    // MARK: Device state

    private func makeSnapshot(_ device: IOBluetoothDevice, address: String, connectedAt: Date) -> SystemConnectedDevice {
        let external = externalInfo[address]
        let name = (device.name ?? "").isEmpty ? (external?.name ?? "") : (device.name ?? "")

        var model: String?
        if let vendor = vendorID(device), vendor != 0x004c, vendor != 0x05ac {
            model = nil
        } else {
            model = SystemDeviceInfoReader.bluetoothProductID(device)
        }
        if SystemAirPodsModel.classify(model) == nil {
            model = SystemDeviceInfoReader.coreAudioModelIdentifier(forAddress: address) ?? model
        }
        if SystemAirPodsModel.classify(model) == nil, let productID = external?.productID {
            model = productID
        }

        var kind = SystemDeviceKind.classify(name: name,
                                             classMajor: device.deviceClassMajor,
                                             classMinor: device.deviceClassMinor,
                                             modelIdentifier: model,
                                             colorID: SystemDeviceInfoReader.bluetoothColorID(device))
        if kind == .generic, let minor = external?.minorType {
            kind = Self.kind(forMinorType: minor) ?? kind
        }

        var battery = SystemDeviceInfoReader.bluetoothBattery(device)
        if let external { battery = battery.merged(with: external.battery) }
        if battery.isEmpty, let hid = hidLevels[address] {
            battery.single = hid
        }

        return SystemConnectedDevice(id: address, name: name, kind: kind, battery: battery,
                                     modelIdentifier: model, connectedAt: connectedAt)
    }

    private func vendorID(_ device: IOBluetoothDevice) -> Int? {
        let selector = NSSelectorFromString("vendorID")
        guard device.responds(to: selector), let number = device.value(forKey: "vendorID") as? NSNumber,
              number.intValue > 0 else { return nil }
        return number.intValue
    }

    private static func kind(forMinorType minor: String) -> SystemDeviceKind? {
        switch minor.lowercased() {
        case "headphones", "headset": return .headphones
        case "speaker", "loudspeaker": return .speaker
        case "keyboard": return .keyboard
        case "mouse": return .mouse
        case "trackpad": return .trackpad
        case "gamepad", "game controller", "joystick": return .gameController
        case "phone", "smartphone": return .phone
        case "computer", "laptop", "desktop": return .computer
        case "watch": return .watch
        default: return nil
        }
    }

    /// Re-reads model and battery for a connected device and stores it.
    private func refreshDevice(_ address: String) {
        guard let device = bluetoothDevices[address],
              let index = devices.firstIndex(where: { $0.id == address }) else { return }
        var snapshot = makeSnapshot(device, address: address, connectedAt: devices[index].connectedAt)
        // Keep values we already had if this read came back empty.
        snapshot.battery = snapshot.battery.merged(with: devices[index].battery)
        if snapshot.kind == .generic, devices[index].kind != .generic { snapshot.kind = devices[index].kind }
        if devices[index] != snapshot { devices[index] = snapshot }
    }

    private func isLow(_ device: SystemConnectedDevice) -> Bool {
        guard let primary = device.battery.primary else { return false }
        return Double(primary) <= Defaults[.lowConnectBatteryThreshold]
    }

    /// `_hasPassedThreshold` per device: one warning per discharge.
    private func checkLowBattery(_ address: String) {
        guard let device = device(address), device.battery.primary != nil else { return }
        guard isLow(device) else {
            lowLatched.remove(address)
            return
        }
        guard !lowLatched.contains(address) else { return }
        // A pending connect announcement handles its own low state.
        guard pendingPresentations[address] == nil else { return }
        lowLatched.insert(address)
        guard Defaults[.warnOnLowConnectBattery], Date() >= suppressUntil else { return }
        present(.lowBattery, device: device)
        if Defaults[.playSoundOnLowConnectBattery] {
            SoundPlayer.play(.lowBattery)
        }
    }

    private func rearmLowBattery() {
        for device in devices where !isLow(device) {
            lowLatched.remove(device.id)
        }
        devices.forEach { checkLowBattery($0.id) }
    }

    // MARK: Enrichment and polling

    /// Model and battery often appear a moment after the link comes up
    /// (CoreAudio route, AAP battery report). Re-read, then fall back to the
    /// HID registry and system_profiler off the main thread.
    private func scheduleEnrichment(_ address: String) {
        enrichmentTasks[address]?.cancel()
        enrichmentTasks[address] = Task { @MainActor in
            for delay in [1.5, 4.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                let manager = SystemConnectivityManager.shared
                manager.refreshDevice(address)
                manager.checkLowBattery(address)
                if let device = manager.device(address), manager.needsBackgroundInfo(device) {
                    manager.runBackgroundRefresh(allowProfiler: true)
                }
            }
            SystemConnectivityManager.shared.enrichmentTasks[address] = nil
        }
    }

    private func needsBackgroundInfo(_ device: SystemConnectedDevice) -> Bool {
        if device.battery.isEmpty { return true }
        if device.kind == .generic { return true }
        if device.kind == .headphones, device.modelIdentifier == nil { return true }
        return false
    }

    private func poll() {
        guard isMonitoring, !devices.isEmpty else { return }
        for device in devices {
            refreshDevice(device.id)
            checkLowBattery(device.id)
        }
        let needsProfiler = devices.contains { needsBackgroundInfo($0) || $0.kind.isAirPods }
        runBackgroundRefresh(allowProfiler: needsProfiler)
    }

    private func runBackgroundRefresh(allowProfiler: Bool) {
        guard !backgroundRefreshInFlight else { return }
        backgroundRefreshInFlight = true
        let useProfiler = allowProfiler
            && Date().timeIntervalSince(lastProfilerRun) >= SystemConstants.Connectivity.profilerThrottle
        if useProfiler { lastProfilerRun = Date() }

        DispatchQueue.global(qos: .utility).async {
            let hid = SystemDeviceInfoReader.hidBatteryLevels()
            let profiler: [String: SystemExternalDeviceInfo]? = useProfiler
                ? SystemDeviceInfoReader.systemProfilerDevices() : nil
            Task { @MainActor in
                SystemConnectivityManager.shared.applyBackground(hid: hid, profiler: profiler)
            }
        }
    }

    private func applyBackground(hid: [String: Int], profiler: [String: SystemExternalDeviceInfo]?) {
        backgroundRefreshInFlight = false
        hidLevels = hid
        if let profiler { externalInfo = profiler }
        for device in devices {
            refreshDevice(device.id)
            // Fresh background readings replace stale ones.
            if let index = devices.firstIndex(where: { $0.id == device.id }) {
                var updated = devices[index]
                var liveBatteryEmpty = true
                if let live = bluetoothDevices[device.id] {
                    liveBatteryEmpty = SystemDeviceInfoReader.bluetoothBattery(live).isEmpty
                }
                if let info = externalInfo[device.id], !info.battery.isEmpty, liveBatteryEmpty {
                    updated.battery = info.battery
                } else if let level = hid[device.id], updated.battery.left == nil, updated.battery.right == nil {
                    updated.battery.single = level
                }
                if updated != devices[index] { devices[index] = updated }
            }
            checkLowBattery(device.id)
        }
    }

    // MARK: Presentation

    private func present(_ kind: SystemConnectivityEventKind, device: SystemConnectedDevice) {
        guard Defaults[.enableConnectivity] else { return }
        let event = SystemConnectivityEvent(kind: kind, device: device)
        currentEvent = event
        lastAnnounced[device.id] = Announcement(kind: kind, date: Date())

        let showsBattery = kind != .disconnected && device.battery.primary != nil
        let wing = showsBattery ? SystemConstants.Connectivity.batteryWing : SystemConstants.Connectivity.labelWing
        let notification = NotchNotification(
            kind: .connectivity,
            category: .connectivity,
            wingWidth: wing,
            duration: Defaults[.connectivityDuration],
            animation: Constants.Animations.notification,
            leading: AnyView(SystemConnectivityNotificationLeading(event: event)),
            trailing: AnyView(SystemConnectivityNotificationTrailing(event: event)))
        NotchController.shared.post(notification)
    }
}

/// ObjC target for IOBluetooth connect / disconnect notifications.
final class SystemBluetoothNotificationTarget: NSObject {
    @objc func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        SystemMainThread.run { SystemConnectivityManager.shared.handleConnected(device) }
    }

    @objc func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        SystemMainThread.run { SystemConnectivityManager.shared.handleDisconnected(device) }
    }
}

/// Receives Bluetooth authorization / power changes after the TCC prompt.
final class SystemBluetoothAuthorizationDelegate: NSObject, CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        SystemMainThread.run { SystemConnectivityManager.shared.authorizationChanged() }
    }
}
