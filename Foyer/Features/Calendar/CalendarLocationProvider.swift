import AppKit
import CoreLocation
import Defaults

/// Shared, lazily-authorised location source for weather and time to leave.
/// Permission is only requested when a feature that needs it is turned on
/// (Alcove shows "unblock" badges until then).
@MainActor
final class CalendarLocationProvider: NSObject, ObservableObject {
    static let shared = CalendarLocationProvider()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastLocation: CLLocation?

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation?, Never>] = []
    private var timeoutTask: Task<Void, Never>?

    private override init() {
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 500
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedAlways: return true
        default: return false
        }
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// Requests permission if it was never asked; opens the Location Services
    /// privacy pane when it was denied.
    func requestAuthorization() {
        Defaults[.hasPromptedLocationPermission] = true
        switch authorizationStatus {
        case .notDetermined:
            NSApp.activate()
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    /// A recent location, or a fresh fix (nil when unauthorised or on timeout).
    func currentLocation() async -> CLLocation? {
        guard isAuthorized else { return nil }
        if let last = lastLocation, Date().timeIntervalSince(last.timestamp) < CalendarStyle.locationMaxAge {
            return last
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            waiters.append(continuation)
            guard waiters.count == 1 else { return }
            manager.requestLocation()
            timeoutTask?.cancel()
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(CalendarStyle.locationTimeout))
                guard !Task.isCancelled else { return }
                self?.resolve(self?.lastLocation)
            }
        }
    }

    private func resolve(_ location: CLLocation?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume(returning: location) }
    }

    fileprivate func handle(locations: [CLLocation]) {
        if let location = locations.last {
            lastLocation = location
        }
        resolve(lastLocation)
    }

    fileprivate func handleFailure() {
        resolve(lastLocation)
    }

    fileprivate func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        guard status != authorizationStatus else { return }
        authorizationStatus = status
        if !isAuthorized { resolve(nil) }
    }
}

extension CalendarLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            CalendarLocationProvider.shared.handle(locations: locations)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            CalendarLocationProvider.shared.handleFailure()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            CalendarLocationProvider.shared.handleAuthorizationChange(status)
        }
    }
}
