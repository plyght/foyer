import Foundation

/// A coalesced now-playing state change pushed to subscribed connections.
struct HelperNowPlayingUpdate {
    var info: [String: Any]?
    var isPlaying: Bool
    var bundleIdentifier: String?
    var infoChanged: Bool
    var isPlayingChanged: Bool
    var bundleChanged: Bool
}

/// Registers for MediaRemote notifications once for the whole helper process
/// and fans changes out to every connection that asked for observation.
/// All state lives on `queue`.
final class HelperNowPlayingObserver {
    static let shared = HelperNowPlayingObserver()

    let queue = DispatchQueue(label: "com.apple.controlcenter.FoyerHelper.nowplaying", qos: .userInitiated)

    private let mediaRemote = HelperMediaRemote.shared
    private var subscribers: [ObjectIdentifier: (HelperNowPlayingUpdate) -> Void] = [:]
    private var notificationTokens: [NSObjectProtocol] = []
    private var isRegistered = false
    private var pendingRefresh: DispatchWorkItem?
    private var lockScreenWidgetVisible = false

    private var lastInfo: NSDictionary?
    private var lastIsPlaying: Bool?
    private var lastBundle: String?
    private var hasDelivered = false

    private init() {}

    // MARK: Subscriptions

    func subscribe(_ owner: AnyObject, handler: @escaping (HelperNowPlayingUpdate) -> Void) {
        let id = ObjectIdentifier(owner)
        queue.async {
            self.subscribers[id] = handler
            self.registerIfNeeded()
            // Deliver the current state to the new subscriber right away.
            self.snapshot { info, isPlaying, bundle in
                handler(HelperNowPlayingUpdate(info: info, isPlaying: isPlaying, bundleIdentifier: bundle,
                                               infoChanged: true, isPlayingChanged: true, bundleChanged: true))
            }
        }
    }

    func unsubscribe(_ owner: AnyObject) {
        let id = ObjectIdentifier(owner)
        queue.async {
            self.subscribers[id] = nil
            self.unregisterIfIdle()
        }
    }

    /// While the lock-screen widget is up, observation stays registered even
    /// if every connection stopped it, and a fresh state is pushed at once.
    func setLockScreenWidgetVisible(_ visible: Bool) {
        queue.async {
            self.lockScreenWidgetVisible = visible
            if visible {
                self.registerIfNeeded()
                self.forcePush()
            } else {
                self.unregisterIfIdle()
            }
        }
    }

    // MARK: Snapshot

    /// Reads info, playing state, client and PID, and builds the sanitized
    /// dictionary. Calls `completion` on `queue`.
    func snapshot(_ completion: @escaping (_ info: [String: Any]?, _ isPlaying: Bool, _ bundle: String?) -> Void) {
        snapshotRaw { raw, isPlaying, client, pid in
            let info = HelperMediaRemote.sanitize(info: raw, isPlaying: isPlaying, client: client, pid: pid)
            completion(info, isPlaying, client?.bundleIdentifier)
        }
    }

    private final class RawBox {
        var info: NSDictionary?
        var isPlaying = false
        var client: HelperMediaRemote.ClientInfo?
        var pid: Int32 = 0
    }

    private func snapshotRaw(_ completion: @escaping (NSDictionary?, Bool, HelperMediaRemote.ClientInfo?, Int32) -> Void) {
        let group = DispatchGroup()
        let box = RawBox()

        group.enter()
        mediaRemote.nowPlayingInfo(on: queue) { value in box.info = value; group.leave() }
        group.enter()
        mediaRemote.isPlaying(on: queue) { value in box.isPlaying = value; group.leave() }
        group.enter()
        mediaRemote.client(on: queue) { value in box.client = value; group.leave() }
        group.enter()
        mediaRemote.applicationPID(on: queue) { value in box.pid = value; group.leave() }

        group.notify(queue: queue) {
            var playing = box.isPlaying
            // Some sources report a playback rate but a stale "is playing".
            if !playing, let rate = box.info?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber, rate.doubleValue > 0 {
                playing = true
            }
            completion(box.info, playing, box.client, box.pid)
        }
    }

    // MARK: Registration

    private func registerIfNeeded() {
        guard !isRegistered else { return }
        isRegistered = true
        mediaRemote.register(on: queue)
        let center = NotificationCenter.default
        for name in HelperMediaRemote.observedNotifications {
            let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.queue.async { self.scheduleRefresh() }
            }
            notificationTokens.append(token)
        }
    }

    private func unregisterIfIdle() {
        guard isRegistered, subscribers.isEmpty, !lockScreenWidgetVisible else { return }
        isRegistered = false
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
        mediaRemote.unregister()
        pendingRefresh?.cancel()
        pendingRefresh = nil
        lastInfo = nil
        lastIsPlaying = nil
        lastBundle = nil
        hasDelivered = false
    }

    /// MediaRemote fires notifications in bursts; coalesce them (50 ms).
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh(force: false) }
        pendingRefresh = work
        queue.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func forcePush() {
        refresh(force: true)
    }

    private func refresh(force: Bool) {
        snapshot { [weak self] info, isPlaying, bundle in
            guard let self else { return }
            let infoObject = info.map { $0 as NSDictionary }
            let infoChanged: Bool
            if let infoObject, let lastInfo = self.lastInfo {
                infoChanged = !infoObject.isEqual(lastInfo)
            } else {
                infoChanged = (infoObject == nil) != (self.lastInfo == nil)
            }
            let playingChanged = self.lastIsPlaying != isPlaying
            let bundleChanged = self.lastBundle != bundle
            let first = !self.hasDelivered

            self.lastInfo = infoObject
            self.lastIsPlaying = isPlaying
            self.lastBundle = bundle
            self.hasDelivered = true

            guard force || first || infoChanged || playingChanged || bundleChanged else { return }
            let update = HelperNowPlayingUpdate(info: info, isPlaying: isPlaying, bundleIdentifier: bundle,
                                                infoChanged: force || first || infoChanged,
                                                isPlayingChanged: force || first || playingChanged,
                                                bundleChanged: force || first || bundleChanged)
            for handler in self.subscribers.values {
                handler(update)
            }
        }
    }
}
