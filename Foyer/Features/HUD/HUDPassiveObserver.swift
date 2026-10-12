import Combine
import Defaults
import Foundation

/// Last-resort HUD trigger: when neither the Accessibility tap nor the key
/// remapper is active (e.g. both HUDs' keys are left to macOS), it observes
/// the volume (CoreAudio listeners) and display brightness (DisplayServices
/// notifications) and presents the HUD on any change, such as changes made
/// from Control Center or other apps.
@MainActor
final class HUDPassiveObserver {
    static let shared = HUDPassiveObserver()

    private var cancellables = Set<AnyCancellable>()
    private var lastDeviceChange = Date.distantPast
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let volume = VolumeManager.shared
        let brightness = HUDBrightnessManager.shared

        volume.$outputDeviceName
            .removeDuplicates()
            .sink { [weak self] _ in self?.lastDeviceChange = Date() }
            .store(in: &cancellables)

        volume.$volume.removeDuplicates().map { _ in () }
            .merge(with: volume.$isMuted.removeDuplicates().map { _ in () })
            .dropFirst(2)
            .sink { [weak self] in self?.volumeChanged() }
            .store(in: &cancellables)

        brightness.$level
            .removeDuplicates { abs($0 - $1) < 0.001 }
            .dropFirst()
            .sink { [weak self] _ in self?.brightnessChanged() }
            .store(in: &cancellables)
    }

    private var shouldPresent: Bool {
        // With the tap active, key presses present the HUD themselves.
        guard !HUDKeyInterceptor.shared.isActive, !HUDKeyRemapper.shared.isActive else { return false }
        if Defaults[.hideWhileGaming], NotchController.shared.hideReasons.contains(.gaming) { return false }
        return true
    }

    private func volumeChanged() {
        guard shouldPresent, Defaults[.enableVolume] else { return }
        // A device switch changes the reported volume; that isn't a user change.
        guard Date().timeIntervalSince(lastDeviceChange) > 0.5 else { return }
        HUDPresenter.present(.volume)
    }

    private func brightnessChanged() {
        guard shouldPresent, Defaults[.enableBrightness] else { return }
        HUDPresenter.present(.brightness)
    }
}
