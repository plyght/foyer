import AppKit
import Combine
import CoreLocation
import Defaults
import MapKit
import SwiftUI

/// "Notify when time to leave": for the next timed event with a physical
/// location, asks MapKit for the travel time (`defaultTransportType`) and,
/// at start − travel − `timeToLeaveBuffer`, shows the `.timeToLeave` live
/// activity for `timeToLeaveDuration` minutes, a Quick Peek, and plays
/// `directions` when `playSoundOnTimeToLeave` is on.
@MainActor
final class TimeToLeaveManager: ObservableObject {
    static let shared = TimeToLeaveManager()

    struct Plan: Equatable {
        let event: CalendarEventItem
        let travelTime: TimeInterval
        let transport: TransportType
        let computedAt: Date

        var leaveDate: Date {
            event.start.addingTimeInterval(-travelTime - Defaults[.timeToLeaveBuffer] * 60)
        }
    }

    /// The plan for the next event with a location.
    @Published private(set) var plan: Plan?
    /// True while the time-to-leave activity is on screen.
    @Published private(set) var isAlerting = false

    private let calendar = CalendarManager.shared
    private let location = CalendarLocationProvider.shared
    private let geocoder = CLGeocoder()
    private var geocodeCache: [String: CLLocationCoordinate2D] = [:]
    private var failedGeocodes: Set<String> = []
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var etaTask: Task<Void, Never>?
    /// `lastTimeToLeaveSignature`: event id + start, so each event alerts once.
    private var alertedSignatures: Set<String> = []
    private var alertEnd: Date?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        let keys: [Defaults._AnyKey] = [.notifyWhenTimeToLeave, .defaultTransportType, .timeToLeaveBuffer, .enableCalendar]
        Defaults.publisher(keys: keys, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.settingsChanged() }
            .store(in: &cancellables)

        calendar.$events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshPlan(force: false) }
            .store(in: &cancellables)

        location.$authorizationStatus
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshPlan(force: true) }
            .store(in: &cancellables)

        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            _ = MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t

        settingsChanged(initial: true)
    }

    private var isEnabled: Bool {
        Defaults[.enableCalendar] && Defaults[.notifyWhenTimeToLeave]
    }

    private func settingsChanged(initial: Bool = false) {
        guard isEnabled else {
            plan = nil
            endAlert()
            return
        }
        if location.authorizationStatus == .notDetermined,
           !initial || !Defaults[.hasPromptedLocationPermission] {
            location.requestAuthorization()
        }
        refreshPlan(force: true)
    }

    // MARK: Planning

    private func candidateEvent(now: Date) -> CalendarEventItem? {
        calendar.activityEvents().first { event in
            guard event.start > now,
                  event.start.timeIntervalSince(now) <= CalendarStyle.timeToLeaveLookahead,
                  hasPhysicalLocation(event) else { return false }
            return true
        }
    }

    private func hasPhysicalLocation(_ event: CalendarEventItem) -> Bool {
        if event.coordinate != nil { return true }
        guard let text = event.location?.lowercased(), !text.isEmpty else { return false }
        let virtual = ["http://", "https://", "zoom.us", "meet.google", "teams.microsoft", "webex", "facetime"]
        return !virtual.contains { text.contains($0) }
    }

    private func refreshPlan(force: Bool) {
        guard isEnabled, location.isAuthorized else {
            if plan != nil { plan = nil }
            return
        }
        let now = Date()
        guard let event = candidateEvent(now: now) else {
            if plan != nil, !isAlerting { plan = nil }
            return
        }
        let transport = Defaults[.defaultTransportType]
        if !force, let plan, plan.event == event, plan.transport == transport,
           now.timeIntervalSince(plan.computedAt) < CalendarStyle.etaRefreshInterval {
            return
        }
        etaTask?.cancel()
        etaTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let travel = await self.travelTime(to: event, transport: transport) else { return }
            guard !Task.isCancelled else { return }
            self.plan = Plan(event: event, travelTime: travel, transport: transport, computedAt: Date())
            self.tick()
        }
    }

    private func destination(for event: CalendarEventItem) async -> CLLocationCoordinate2D? {
        if let coordinate = event.coordinate { return coordinate }
        guard let address = event.location else { return nil }
        if let cached = geocodeCache[address] { return cached }
        if failedGeocodes.contains(address) { return nil }
        do {
            let placemarks = try await geocoder.geocodeAddressString(address)
            if let coordinate = placemarks.first?.location?.coordinate {
                geocodeCache[address] = coordinate
                return coordinate
            }
        } catch {}
        failedGeocodes.insert(address)
        return nil
    }

    private func travelTime(to event: CalendarEventItem, transport: TransportType) async -> TimeInterval? {
        guard let here = await location.currentLocation(),
              let target = await destination(for: event) else { return nil }

        if let eta = await Self.eta(from: here.coordinate, to: target, type: Self.mapKitType(transport)) {
            return eta
        }
        // Transit directions are not available everywhere: fall back to driving.
        if transport == .transit {
            return await Self.eta(from: here.coordinate, to: target, type: .automobile)
        }
        return nil
    }

    private static func mapKitType(_ transport: TransportType) -> MKDirectionsTransportType {
        switch transport {
        case .automobile: return .automobile
        case .walking: return .walking
        case .transit: return .transit
        }
    }

    private static func eta(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D,
                            type: MKDirectionsTransportType) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = type
        request.departureDate = Date()
        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculateETA()
            return response.expectedTravelTime
        } catch {
            return nil
        }
    }

    // MARK: Alerting

    private func tick() {
        let now = Date()
        if isAlerting, let end = alertEnd, now >= end {
            endAlert()
        }
        guard isEnabled, let plan else { return }

        // Keep the ETA fresh while an event is pending.
        if now.timeIntervalSince(plan.computedAt) >= CalendarStyle.etaRefreshInterval, !isAlerting {
            refreshPlan(force: true)
        }

        let signature = "\(plan.event.id)|\(Int(plan.event.start.timeIntervalSince1970))"
        guard !alertedSignatures.contains(signature),
              now >= plan.leaveDate, now < plan.event.start else { return }
        alertedSignatures.insert(signature)
        beginAlert(plan: plan, now: now)
    }

    private func beginAlert(plan: Plan, now: Date) {
        let duration = max(1, Defaults[.timeToLeaveDuration]) * 60
        alertEnd = min(now.addingTimeInterval(duration), plan.event.start)
        isAlerting = true

        let controller = NotchController.shared
        controller.setActivity(LiveActivity(
            id: .timeToLeave,
            wingWidth: CalendarStyle.wing,
            priority: CalendarStyle.timeToLeavePriority,
            leading: AnyView(TimeToLeaveCompactLeading()),
            trailing: AnyView(TimeToLeaveCompactTrailing())))
        controller.undismiss(.timeToLeave)
        controller.touchActivity(.timeToLeave)
        controller.showQuickPeek(QuickPeek(
            source: .timeToLeave,
            duration: Defaults[.calendarPeekDuration],
            content: AnyView(TimeToLeavePeekView(plan: plan))))

        if Defaults[.playSoundOnTimeToLeave] {
            SoundPlayer.play(.directions)
        }
    }

    private func endAlert() {
        alertEnd = nil
        if isAlerting {
            isAlerting = false
            NotchController.shared.removeActivity(.timeToLeave)
        }
    }

    static func symbol(for transport: TransportType) -> String {
        switch transport {
        case .automobile: return "car.fill"
        case .walking: return "figure.walk"
        case .transit: return "tram.fill"
        }
    }
}

// MARK: - Views

struct TimeToLeaveCompactLeading: View {
    @ObservedObject private var manager = TimeToLeaveManager.shared

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: TimeToLeaveManager.symbol(for: manager.plan?.transport ?? Defaults[.defaultTransportType]))
                .font(.system(size: CalendarStyle.compactGlyphSize, weight: .semibold))
                .foregroundStyle(CalendarStyle.sky)
            Spacer(minLength: 0)
        }
        .padding(.leading, CalendarStyle.wingInset)
    }
}

/// Minutes until the event starts.
struct TimeToLeaveCompactTrailing: View {
    @ObservedObject private var manager = TimeToLeaveManager.shared

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            if let plan = manager.plan {
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    Text(CalendarFormat.countdown(plan.event.start.timeIntervalSince(context.date)))
                        .font(.system(size: CalendarStyle.compactFontSize, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(CalendarStyle.sky)
                        .fixedSize()
                }
            }
        }
        .padding(.trailing, CalendarStyle.wingInset)
    }
}

/// Quick Peek: transport glyph + travel time; "Time to leave" + event title.
struct TimeToLeavePeekView: View {
    let plan: TimeToLeaveManager.Plan
    @Environment(\.notchGeometry) private var geometry

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: TimeToLeaveManager.symbol(for: plan.transport))
                    .font(.system(size: CalendarStyle.compactGlyphSize, weight: .semibold))
                    .foregroundStyle(CalendarStyle.sky)
                Spacer(minLength: 0)
                Text(CalendarFormat.duration(plan.travelTime))
                    .font(.system(size: CalendarStyle.compactFontSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(CalendarStyle.sky)
                    .fixedSize()
            }
            .padding(.horizontal, CalendarStyle.peekHorizontalInset)
            .frame(height: max(geometry.closedSize.height, 24))

            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(plan.event.calendarColor)
                    .frame(width: CalendarStyle.peekBarWidth, height: CalendarStyle.peekBarHeight)
                Text(String(localized: "Time to leave"))
                    .font(.system(size: CalendarStyle.peekTitleSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
                Text(plan.event.title)
                    .font(.system(size: CalendarStyle.peekDetailSize, weight: .medium))
                    .foregroundStyle(CalendarStyle.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, CalendarStyle.peekHorizontalInset + 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
