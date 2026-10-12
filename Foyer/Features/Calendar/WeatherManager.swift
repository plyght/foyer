import AppKit
import Combine
import CoreLocation
import Defaults
import SwiftUI
import WeatherKit

/// A cached weather reading. Temperatures are stored in Celsius and formatted
/// for the user's locale on display.
struct CalendarWeatherSnapshot: Codable, Equatable {
    enum Source: String, Codable { case weatherKit, openMeteo }

    var temperature: Double
    var high: Double?
    var low: Double?
    /// Probability 0…1.
    var precipitationChance: Double?
    var condition: String
    var symbolName: String
    var isDaylight: Bool
    var fetchedAt: Date
    var latitude: Double
    var longitude: Double
    var source: Source

    var isFresh: Bool { Date().timeIntervalSince(fetchedAt) < CalendarStyle.weatherTTL }
}

enum WeatherFormat {
    private static let formatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .temperatureWithoutUnit
        f.unitStyle = .short
        f.numberFormatter.maximumFractionDigits = 0
        return f
    }()

    /// "18°" in the locale's preferred unit.
    static func temperature(_ celsius: Double) -> String {
        formatter.string(from: Measurement(value: celsius, unit: UnitTemperature.celsius))
    }

    /// "H:21° L:12°".
    static func highLow(_ snapshot: CalendarWeatherSnapshot) -> String {
        guard let high = snapshot.high, let low = snapshot.low else { return snapshot.condition }
        return "H:\(temperature(high)) L:\(temperature(low))"
    }

    /// "40%".
    static func precipitation(_ chance: Double?) -> String? {
        guard let chance else { return nil }
        return "\(Int((chance * 100).rounded()))%"
    }
}

/// Weather for the empty-day calendar and the lock-screen widget. WeatherKit
/// is tried first (it needs a provisioning entitlement that ad-hoc builds do
/// not carry); on failure Foyer falls back to the free, key-less Open-Meteo
/// API. Results are cached for 30 minutes and persisted across launches. It
/// only runs when a consumer is enabled and Location is authorised.
@MainActor
final class WeatherManager: ObservableObject {
    static let shared = WeatherManager()

    @Published private(set) var snapshot: CalendarWeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let location = CalendarLocationProvider.shared
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var fetchTask: Task<Void, Never>?
    private var weatherKitUnavailable = false
    private var started = false

    private init() {
        if let data = Defaults[.calendarCachedWeather],
           let cached = try? JSONDecoder().decode(CalendarWeatherSnapshot.self, from: data) {
            snapshot = cached
        }
    }

    /// Whether any consumer wants weather right now.
    var isNeeded: Bool {
        (Defaults[.enableCalendar] && Defaults[.showWeatherOnEmptyDay])
            || (Defaults[.enableLockScreen] && Defaults[.allowWeatherWidgetWhenLocked])
    }

    var needsLocationPermission: Bool { !location.isAuthorized }

    func start() {
        guard !started else { return }
        started = true

        let keys: [Defaults._AnyKey] = [.showWeatherOnEmptyDay, .allowWeatherWidgetWhenLocked, .enableCalendar, .enableLockScreen]
        Defaults.publisher(keys: keys, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.configurationChanged(userInitiated: true) }
            .store(in: &cancellables)

        location.$authorizationStatus
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.configurationChanged(userInitiated: false) }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshIfNeeded() }
            .store(in: &cancellables)

        configurationChanged(userInitiated: false)
    }

    private func configurationChanged(userInitiated: Bool) {
        guard isNeeded else {
            refreshTimer?.invalidate()
            refreshTimer = nil
            return
        }
        if location.authorizationStatus == .notDetermined {
            // Ask lazily, and only when the user turned a weather feature on
            // (or at launch if it was already on and never asked).
            if userInitiated || !Defaults[.hasPromptedLocationPermission] {
                location.requestAuthorization()
            }
            return
        }
        if refreshTimer == nil {
            let timer = Timer(timeInterval: CalendarStyle.weatherTTL, repeats: true) { [weak self] _ in
                _ = MainActor.assumeIsolated { self?.refresh(force: true) }
            }
            timer.tolerance = 60
            RunLoop.main.add(timer, forMode: .common)
            refreshTimer = timer
        }
        refreshIfNeeded()
    }

    /// Fetches when the cache is stale.
    func refreshIfNeeded() {
        if let snapshot, snapshot.isFresh { return }
        refresh(force: false)
    }

    func refresh(force: Bool) {
        guard isNeeded, location.isAuthorized else { return }
        guard fetchTask == nil else { return }
        if !force, let snapshot, snapshot.isFresh { return }
        isLoading = true
        fetchTask = Task { @MainActor [weak self] in
            await self?.performFetch()
            self?.fetchTask = nil
            self?.isLoading = false
        }
    }

    private func performFetch() async {
        guard let here = await location.currentLocation() else {
            lastError = String(localized: "Location unavailable")
            return
        }
        var result: CalendarWeatherSnapshot?
        if !weatherKitUnavailable {
            do {
                result = try await fetchWeatherKit(at: here)
            } catch {
                // Missing WeatherKit entitlement / auth failure: stop trying this session.
                weatherKitUnavailable = true
            }
        }
        if result == nil {
            do {
                result = try await fetchOpenMeteo(at: here)
            } catch {
                lastError = error.localizedDescription
            }
        }
        guard let result else { return }
        lastError = nil
        if result != snapshot {
            withAnimation(Constants.Animations.standard) { snapshot = result }
        }
        if let data = try? JSONEncoder().encode(result) {
            Defaults[.calendarCachedWeather] = data
        }
    }

    // MARK: WeatherKit

    private func fetchWeatherKit(at location: CLLocation) async throws -> CalendarWeatherSnapshot {
        let weather = try await WeatherService.shared.weather(for: location)
        let current = weather.currentWeather
        let today = weather.dailyForecast.forecast.first
        return CalendarWeatherSnapshot(
            temperature: current.temperature.converted(to: .celsius).value,
            high: today.map { $0.highTemperature.converted(to: .celsius).value },
            low: today.map { $0.lowTemperature.converted(to: .celsius).value },
            precipitationChance: today.map { $0.precipitationChance },
            condition: current.condition.description,
            symbolName: Self.filledSymbol(current.symbolName),
            isDaylight: current.isDaylight,
            fetchedAt: Date(),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            source: .weatherKit)
    }

    private static func filledSymbol(_ name: String) -> String {
        if name.hasSuffix(".fill") { return name }
        let filled = name + ".fill"
        if NSImage(systemSymbolName: filled, accessibilityDescription: nil) != nil { return filled }
        return name
    }

    // MARK: Open-Meteo (no key)

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int?
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double?]?
            let temperature_2m_min: [Double?]?
            let precipitation_probability_max: [Double?]?
        }
        let current: Current
        let daily: Daily?
    }

    private func fetchOpenMeteo(at location: CLLocation) async throws -> CalendarWeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let isDay = (decoded.current.is_day ?? 1) == 1
        let code = decoded.current.weather_code
        let high = decoded.daily?.temperature_2m_max?.first ?? nil
        let low = decoded.daily?.temperature_2m_min?.first ?? nil
        let precipitation = decoded.daily?.precipitation_probability_max?.first ?? nil
        return CalendarWeatherSnapshot(
            temperature: decoded.current.temperature_2m,
            high: high,
            low: low,
            precipitationChance: precipitation.map { $0 / 100 },
            condition: WMOCode.description(code),
            symbolName: WMOCode.symbol(code, isDay: isDay),
            isDaylight: isDay,
            fetchedAt: Date(),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            source: .openMeteo)
    }
}

/// WMO weather interpretation codes used by Open-Meteo.
private enum WMOCode {
    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 80, 81: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95: return "cloud.bolt.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func description(_ code: Int) -> String {
        switch code {
        case 0: return String(localized: "Clear")
        case 1: return String(localized: "Mostly Clear")
        case 2: return String(localized: "Partly Cloudy")
        case 3: return String(localized: "Cloudy")
        case 45, 48: return String(localized: "Foggy")
        case 51, 53, 55: return String(localized: "Drizzle")
        case 56, 57: return String(localized: "Freezing Drizzle")
        case 61, 80: return String(localized: "Light Rain")
        case 63, 81: return String(localized: "Rain")
        case 65, 82: return String(localized: "Heavy Rain")
        case 66, 67: return String(localized: "Freezing Rain")
        case 71, 85: return String(localized: "Light Snow")
        case 73: return String(localized: "Snow")
        case 75, 86: return String(localized: "Heavy Snow")
        case 77: return String(localized: "Snow Grains")
        case 95: return String(localized: "Thunderstorms")
        case 96, 99: return String(localized: "Thunderstorms with Hail")
        default: return String(localized: "Cloudy")
        }
    }
}

// MARK: - Lock-screen widget

/// Weather widget for the lock screen (drawn on the lock feature's glass
/// material): symbol, temperature, condition, high/low and precipitation.
struct WeatherLockWidget: View {
    @ObservedObject private var weather = WeatherManager.shared
    @ObservedObject private var location = CalendarLocationProvider.shared
    @Default(.weatherStyle) private var weatherStyle

    var body: some View {
        Group {
            if let snapshot = weather.snapshot {
                HStack(spacing: 12) {
                    Image(systemName: snapshot.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 30, weight: .medium))
                        .frame(width: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.condition)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Text(WeatherFormat.highLow(snapshot))
                                .monospacedDigit()
                            if let rain = WeatherFormat.precipitation(snapshot.precipitationChance), weatherStyle == .symbol {
                                Label(rain, systemImage: "drop.fill")
                                    .labelStyle(.titleAndIcon)
                                    .monospacedDigit()
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(WeatherFormat.temperature(snapshot.temperature))
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: location.isAuthorized ? "cloud.sun.fill" : "location.slash.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 22, weight: .medium))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Weather"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(location.isAuthorized
                             ? (weather.isLoading ? String(localized: "Updating…") : String(localized: "Unavailable"))
                             : String(localized: "Location access needed"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, .dark)
        .onAppear { weather.refreshIfNeeded() }
    }
}
