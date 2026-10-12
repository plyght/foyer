import AppKit
import Combine
import Defaults
import SwiftUI

/// Per-screen interaction state: geometry, hover, expansion, rubber band and
/// swipe handling. Content comes from `NotchController.shared`.
@MainActor
final class NotchViewModel: ObservableObject {
    let screenID: CGDirectDisplayID
    let controller = NotchController.shared

    @Published private(set) var geometry: NotchGeometry = .zero
    @Published private(set) var isHovering = false
    @Published private(set) var isExpanded = false
    /// Content opacity of the expanded page; it fades before the shape closes.
    @Published private(set) var expandedContentVisible = false
    @Published private(set) var currentPageID: ExpandedPageID?
    /// Rubber-band stretch while pulling toward open (scroll points).
    @Published private(set) var stretch: CGFloat = 0

    weak var panel: NotchPanel?
    /// Panel frame in screen coordinates; the notch is drawn top-centred in it.
    var panelFrame: CGRect = .zero

    private var hoverTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let swipes = SwipeTracker()

    init(screenID: CGDirectDisplayID) {
        self.screenID = screenID
        controller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func updateGeometry(for screen: NSScreen) {
        let new = NotchGeometry.compute(for: screen, forceSimulated: Defaults[.forceSimulatedNotch])
        if new != geometry { geometry = new }
    }

    // MARK: Derived presentation

    enum Presentation: Equatable {
        case closed
        case activity(LiveActivityID)
        case notification(NotificationKind)
        case peek(UUID)
        case expanded(ExpandedPageID?)
    }

    var presentation: Presentation {
        if isExpanded { return .expanded(currentPage?.id) }
        if let n = controller.notification { return .notification(n.kind) }
        if let p = controller.quickPeek { return .peek(p.id) }
        if let a = controller.visibleActivity { return .activity(a.id) }
        return .closed
    }

    var isHidden: Bool { controller.isHidden(on: screenID) }

    var currentPage: ExpandedPage? {
        let pages = controller.orderedPages
        if let id = currentPageID, let page = pages.first(where: { $0.id == id }) { return page }
        return pages.first
    }

    /// Body size of the shape (without the concave ears).
    var bodySize: CGSize {
        let G = Constants.Geometry.self
        let closed = geometry.closedSize
        var size: CGSize
        switch presentation {
        case .expanded:
            let page = currentPage
            size = CGSize(width: page?.width ?? geometry.expandedSize.width + G.expandedBodyExtra,
                          height: page?.height ?? geometry.expandedSize.height)
        case .peek:
            let peek = controller.quickPeek
            size = CGSize(width: closed.width + (peek?.extraWidth ?? G.peekExtraWidth),
                          height: peek?.height ?? G.peekHeight)
        case .notification:
            let n = controller.notification
            size = CGSize(width: closed.width + 2 * (n?.wingWidth ?? G.activityWing),
                          height: n?.height ?? closed.height)
        case .activity:
            let wing = controller.visibleActivity?.wingWidth ?? G.activityWing
            size = CGSize(width: closed.width + 2 * wing, height: closed.height)
        case .closed:
            size = closed
        }
        if !isExpanded {
            if isHovering {
                size.width = (size.width * G.hoverWidthScale).rounded()
                size.height += G.hoverExtraHeight
            }
            size.width += stretch * G.rubberBandWidth
            size.height += stretch * G.rubberBandHeight
        }
        return size
    }

    var topCornerRadius: CGFloat {
        let G = Constants.Geometry.self
        switch presentation {
        case .expanded: return G.expandedTopRadius
        case .peek: return G.peekTopRadius
        default: return G.closedTopRadius
        }
    }

    var bottomCornerRadius: CGFloat {
        let G = Constants.Geometry.self
        switch presentation {
        case .expanded: return G.expandedBottomRadius
        case .peek: return G.peekBottomRadius
        default: return G.closedBottomRadius
        }
    }

    var shapeStyle: NotchShape.Style {
        geometry.style == .pill && !isExpanded ? .pill : .notch
    }

    /// Full frame of the shape including ears, in panel (SwiftUI, top-left) coordinates.
    var shapeFrame: CGRect {
        let body = bodySize
        let ears = shapeStyle == .notch ? 2 * topCornerRadius : 0
        let width = body.width + ears
        let top: CGFloat = geometry.style == .pill && !isExpanded ? Constants.Geometry.pillTopInset : 0
        return CGRect(x: (Constants.Geometry.panelSize.width - width) / 2, y: top, width: width, height: body.height)
    }

    /// Shape frame in global screen coordinates (AppKit, bottom-left origin).
    var screenHitRect: CGRect {
        let f = shapeFrame
        return CGRect(x: panelFrame.minX + f.minX,
                      y: panelFrame.maxY - f.maxY,
                      width: f.width,
                      height: f.height).insetBy(dx: -4, dy: -4)
    }

    // MARK: Hover / mouse

    func mouseMoved(to point: CGPoint) {
        guard !isHidden else { setHovering(false); return }
        // While closed with no notch, extend the hot zone to the top edge so
        // the cursor slamming into the menu bar still counts.
        var rect = screenHitRect
        if !isExpanded { rect = rect.union(CGRect(x: rect.minX, y: rect.maxY, width: rect.width, height: 8)) }
        setHovering(rect.contains(point))
    }

    private func setHovering(_ hovering: Bool) {
        panel?.ignoresMouseEvents = !hovering
        guard hovering != isHovering else { return }
        withAnimation(hovering ? Constants.Animations.hoverIn : Constants.Animations.hoverOut) {
            isHovering = hovering
        }
        hoverTask?.cancel()
        if hovering {
            closeTask?.cancel()
            if Defaults[.expandNotchOnHover], !isExpanded {
                let delay = Defaults[.hoverDuration]
                hoverTask = Task { @MainActor in
                    if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                    guard !Task.isCancelled, self.isHovering else { return }
                    self.open()
                }
            }
        } else if isExpanded {
            // Collapse on mouse exit (Part C §2.3) after a short debounce.
            closeTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.1))
                guard !Task.isCancelled, !self.isHovering else { return }
                self.close()
            }
        }
    }

    func mouseDownOutside(at point: CGPoint) {
        if isExpanded, !screenHitRect.contains(point) { close() }
    }

    func tap() {
        Haptics.perform(.generic)
        isExpanded ? close() : open()
    }

    // MARK: Open / close

    func open(page: ExpandedPageID? = nil) {
        guard !controller.orderedPages.isEmpty || page != nil else { return }
        closeTask?.cancel()
        controller.dismissQuickPeek()
        if let page { currentPageID = page }
        withAnimation(Constants.Animations.open) {
            isExpanded = true
            stretch = 0
        }
        withAnimation(Constants.Animations.fade.delay(Constants.Animations.contentDelay)) {
            expandedContentVisible = true
        }
    }

    func close() {
        guard isExpanded else { return }
        closeTask?.cancel()
        withAnimation(.easeOut(duration: Constants.Animations.contentOutDuration)) {
            expandedContentVisible = false
        }
        closeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Constants.Animations.contentOutDuration / 2))
            guard !Task.isCancelled else { return }
            withAnimation(Constants.Animations.close) { self.isExpanded = false }
        }
    }

    func cyclePage() {
        let pages = controller.orderedPages
        guard pages.count > 1, let current = currentPage,
              let index = pages.firstIndex(where: { $0.id == current.id }) else { return }
        let next = pages[(index + 1) % pages.count]
        withAnimation(Constants.Animations.contentSwap) { currentPageID = next.id }
    }

    // MARK: Swipes

    func handleScroll(_ event: NSEvent) {
        guard !isHidden else { return }
        guard let outcome = swipes.consume(event, expanded: isExpanded) else { return }
        apply(outcome)
    }

    private func apply(_ outcome: SwipeTracker.Outcome) {
        switch outcome {
        case .stretch(let amount):
            let canOpen = Defaults[.swipeToToggle] && controller.dismissedActivities.isEmpty
            let value = canOpen ? min(max(amount, 0), 60) : 0
            withAnimation(.interactiveSpring) { stretch = value }
        case .releaseStretch:
            withAnimation(Constants.Animations.hoverOut) { stretch = 0 }
        case .down:
            // Restore a dismissed activity, otherwise toggle open.
            if Defaults[.swipeToCycleActivity], controller.restoreDismissedActivity() {
                Haptics.perform(.generic)
                withAnimation(Constants.Animations.hoverOut) { stretch = 0 }
            } else if Defaults[.swipeToToggle] {
                Haptics.perform(.generic)
                open()
            }
        case .up:
            guard Defaults[.swipeToDismiss] || Defaults[.swipeToCycleActivity],
                  !Defaults[.naturalMovement] else { return }
            Haptics.perform(.generic)
            if controller.quickPeek != nil {
                controller.dismissQuickPeek()
            } else if controller.notification != nil {
                controller.dismissNotification()
            } else {
                controller.dismissVisibleActivity()
            }
        case .expandedUp:
            guard Defaults[.swipeToToggle] else { return }
            Haptics.perform(.generic)
            close()
        case .expandedDown:
            Haptics.perform(.generic)
            cyclePage()
        case .horizontal(let forward):
            guard Defaults[.swipeToSkip] else { return }
            let next = Defaults[.naturalMovement] ? !forward : forward
            Haptics.perform(.generic)
            controller.send(next ? .next : .previous)
        }
    }
}

/// Accumulates one trackpad gesture (began…ended) and decides what it means.
/// Thresholds from teardown §7.4 / Part I: vertical 35, reset on a 15 pt
/// reversal, horizontal 70 (35 inside the expanded panel), expanded close 105,
/// expanded page switch 75, and a 0.5 s guard between gestures.
@MainActor
final class SwipeTracker {
    enum Outcome {
        case stretch(CGFloat), releaseStretch
        case down, up
        case expandedUp, expandedDown
        case horizontal(forward: Bool)
    }

    private enum Axis { case vertical, horizontal }

    private var axis: Axis?
    private var accumulated: CGFloat = 0
    private var peak: CGFloat = 0
    private var fired = false
    private var ignoreGesture = false
    private var lastFire: Date = .distantPast

    func consume(_ event: NSEvent, expanded: Bool) -> Outcome? {
        // Only continuous trackpad gestures, not momentum or wheel mice.
        guard event.hasPreciseScrollingDeltas, event.momentumPhase == [] else { return nil }

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            axis = nil; accumulated = 0; peak = 0; fired = false
            ignoreGesture = Date().timeIntervalSince(lastFire) < Constants.Durations.swipeReset
            return nil
        }
        if ignoreGesture { return nil }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            defer { axis = nil; accumulated = 0; peak = 0 }
            if !fired, axis == .vertical, !expanded, accumulated > Constants.Swipes.verticalSuccess {
                markFired()
                return .down
            }
            return axis == .vertical && !expanded ? .releaseStretch : nil
        }

        guard event.phase.contains(.changed) else { return nil }

        // Normalise to physical finger motion: positive = fingers moving down / right.
        let inverted = event.isDirectionInvertedFromDevice
        let fingerDown = inverted ? event.scrollingDeltaY : -event.scrollingDeltaY
        let fingerRight = inverted ? event.scrollingDeltaX : -event.scrollingDeltaX

        if axis == nil {
            guard abs(fingerDown) > 0.5 || abs(fingerRight) > 0.5 else { return nil }
            axis = abs(fingerRight) > abs(fingerDown) ? .horizontal : .vertical
        }
        guard !fired else { return nil }

        let delta = axis == .vertical ? fingerDown : fingerRight
        accumulated += delta
        // A reversal of ≥ 15 pt from the running extreme resets the distance.
        if peak == 0 || (accumulated.sign == peak.sign && abs(accumulated) >= abs(peak)) {
            peak = accumulated
        } else if abs(peak - accumulated) >= Constants.Swipes.verticalReset {
            accumulated = 0
            peak = 0
        }

        switch axis {
        case .horizontal:
            let threshold = expanded ? Constants.Swipes.expandedHorizontalSuccess : Constants.Swipes.horizontalSuccess
            if abs(accumulated) > threshold {
                markFired()
                return .horizontal(forward: accumulated > 0)
            }
        case .vertical:
            if expanded {
                if accumulated < -Constants.Swipes.expandedCloseSuccess { markFired(); return .expandedUp }
                if accumulated > Constants.Swipes.expandedPageSuccess { markFired(); return .expandedDown }
            } else {
                if accumulated < -Constants.Swipes.cycleActivitySuccess { markFired(); return .up }
                // Opening resolves on Ended; follow the finger until then.
                return .stretch(accumulated)
            }
        case nil:
            break
        }
        return nil
    }

    private func markFired() {
        fired = true
        lastFire = Date()
    }
}
