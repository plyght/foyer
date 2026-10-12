import Defaults
import SwiftUI

/// Entry point of the Calendar feature: EventKit, the calendar live activity,
/// expanded page and Quick Peeks, the hourly chime, time to leave, weather
/// and Focus.
enum CalendarModule {
    @MainActor
    static func start() {
        CalendarManager.shared.start()
        CalendarLiveController.shared.start()
        TimeToLeaveManager.shared.start()
        WeatherManager.shared.start()
        FocusManager.shared.start()
    }
}
