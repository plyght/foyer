import AppKit
import Foundation

/// A MediaRemote-backed source of now-playing snapshots.
@MainActor
protocol NowPlayingRemoteBackend: AnyObject {
    var name: String { get }
    /// `update` receives every new snapshot (nil when nothing is playing);
    /// `failure` is called once if the backend turns out to be unusable.
    func start(update: @escaping @MainActor (NowPlayingSnapshot?) -> Void, failure: @escaping @MainActor () -> Void)
    func stop()
    func refresh()
    func perform(_ command: NowPlayingRemoteCommand)
    func setLockScreenWidgetVisible(_ visible: Bool)
}

// MARK: - Helper (XPC)

/// Allowed classes for dictionaries exchanged with FoyerHelper.xpc.
enum NowPlayingXPCInterfaces {
    static let plistClasses: Set<AnyHashable> = NSSet(array: [
        NSDictionary.self, NSArray.self, NSString.self, NSNumber.self, NSData.self, NSDate.self,
    ]) as! Set<AnyHashable>

    static func helperInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: FoyerHelperProtocol.self)
        let replySelectors: [Selector] = [
            #selector(FoyerHelperProtocol.getNowPlayingInfo(_:)),
            #selector(FoyerHelperProtocol.getNowPlayingInfo(forBundleIdentifier:reply:)),
            #selector(FoyerHelperProtocol.getNowPlayingSource(_:)),
            #selector(FoyerHelperProtocol.checkSupportedCommands(_:)),
            #selector(FoyerHelperProtocol.checkSupportedCommands(forBundleIdentifier:reply:)),
        ]
        for selector in replySelectors {
            interface.setClasses(plistClasses, for: selector, argumentIndex: 0, ofReply: true)
        }
        return interface
    }

    static func clientInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: FoyerHelperClientProtocol.self)
        interface.setClasses(plistClasses, for: #selector(FoyerHelperClientProtocol.nowPlayingDidChange(_:)),
                             argumentIndex: 0, ofReply: false)
        return interface
    }
}

/// Exported object receiving the helper's pushes (called on an XPC queue).
final class NowPlayingHelperClientReceiver: NSObject, FoyerHelperClientProtocol {
    weak var backend: NowPlayingHelperBackend?

    func nowPlayingDidChange(_ info: [String: Any]?) {
        let snapshot = NowPlayingSnapshot(helperInfo: info)
        Task { @MainActor [weak self] in
            self?.backend?.receive(snapshot)
        }
    }

    func isPlayingDidChange(_ isPlaying: Bool) {
        Task { @MainActor [weak self] in
            self?.backend?.receivePlaying(isPlaying)
        }
    }

    func nowPlayingApplicationDidChange(_ bundleIdentifier: String?) {
        Task { @MainActor [weak self] in
            self?.backend?.refresh()
        }
    }
}

/// Talks to FoyerHelper.xpc over a bidirectional NSXPCConnection.
@MainActor
final class NowPlayingHelperBackend: NowPlayingRemoteBackend {
    let name = "FoyerHelper"

    private var connection: NSXPCConnection?
    private let receiver = NowPlayingHelperClientReceiver()
    private var update: (@MainActor (NowPlayingSnapshot?) -> Void)?
    private var failure: (@MainActor () -> Void)?
    private var current: NowPlayingSnapshot?
    private var hasAnswered = false
    private var reconnects = 0
    private var livenessTask: Task<Void, Never>?
    private var lockScreenVisible = false

    init() {
        receiver.backend = self
    }

    func start(update: @escaping @MainActor (NowPlayingSnapshot?) -> Void, failure: @escaping @MainActor () -> Void) {
        self.update = update
        self.failure = failure
        connect()
    }

    func stop() {
        livenessTask?.cancel()
        livenessTask = nil
        proxy()?.stopNowPlayingObservation()
        let old = connection
        connection = nil
        old?.invalidate()
        update = nil
        failure = nil
    }

    private func connect() {
        let connection = NSXPCConnection(serviceName: FoyerHelperConstants.serviceName)
        connection.remoteObjectInterface = NowPlayingXPCInterfaces.helperInterface()
        connection.exportedInterface = NowPlayingXPCInterfaces.clientInterface()
        connection.exportedObject = receiver
        let identifier = ObjectIdentifier(connection)
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.connectionLost(identifier, invalidated: false) }
        }
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connectionLost(identifier, invalidated: true) }
        }
        self.connection = connection
        connection.resume()

        guard let helper = proxy() else { fail(); return }
        helper.startNowPlayingObservation()
        if lockScreenVisible { helper.postLockScreenWidgetIsShown() }

        // The helper must answer within the timeout, otherwise fall back.
        livenessTask?.cancel()
        livenessTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NowPlayingMetrics.helperTimeout))
            guard let self, !Task.isCancelled, !self.hasAnswered else { return }
            self.fail()
        }
        helper.getIsPlaying { [weak self] _ in
            Task { @MainActor in self?.markAnswered() }
        }
        refresh()
    }

    private func markAnswered() {
        hasAnswered = true
        reconnects = 0
        livenessTask?.cancel()
        livenessTask = nil
    }

    private func connectionLost(_ identifier: ObjectIdentifier, invalidated: Bool) {
        // Ignore stale connections and connections stopped on purpose.
        guard let connection, ObjectIdentifier(connection) == identifier else { return }
        if invalidated { self.connection = nil }
        guard hasAnswered, reconnects < 3 else { fail(); return }
        reconnects += 1
        // Interrupted helpers relaunch on the next message; invalidated ones need a new connection.
        if invalidated {
            hasAnswered = false
            connect()
        } else {
            proxy()?.startNowPlayingObservation()
            refresh()
        }
    }

    private func fail() {
        let handler = failure
        stop()
        handler?()
    }

    private func proxy() -> FoyerHelperProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { _ in } as? FoyerHelperProtocol
    }

    func refresh() {
        proxy()?.getNowPlayingInfo { [weak self] info in
            let snapshot = NowPlayingSnapshot(helperInfo: info)
            Task { @MainActor in
                self?.markAnswered()
                self?.receive(snapshot)
            }
        }
    }

    func receive(_ snapshot: NowPlayingSnapshot?) {
        current = snapshot
        update?(snapshot)
    }

    func receivePlaying(_ isPlaying: Bool) {
        guard var snapshot = current, snapshot.isPlaying != isPlaying else { return }
        // Freeze the extrapolated position at the moment of the change.
        let now = Date()
        snapshot.elapsed = snapshot.elapsed(at: now)
        snapshot.timestamp = now
        snapshot.isPlaying = isPlaying
        current = snapshot
        update?(snapshot)
        refresh()
    }

    func perform(_ command: NowPlayingRemoteCommand) {
        guard let helper = proxy() else { return }
        switch command {
        case .togglePlayPause: helper.playPause()
        case .next: helper.nextTrack()
        case .previous: helper.previousTrack()
        case .seek(let position): helper.setPlayerPosition(position)
        case .setShuffle(let mode): helper.setShuffleMode(mode.rawValue)
        case .setRepeat(let mode): helper.setRepeatMode(mode.rawValue)
        }
    }

    func setLockScreenWidgetVisible(_ visible: Bool) {
        lockScreenVisible = visible
        if visible {
            proxy()?.postLockScreenWidgetIsShown()
        } else {
            proxy()?.postLockScreenWidgetIsHidden()
        }
    }
}

// MARK: - In-process MediaRemote

@MainActor
final class NowPlayingInProcessBackend: NowPlayingRemoteBackend {
    let name = "MediaRemote"

    private let bridge = NowPlayingMediaRemoteBridge.shared
    private var update: (@MainActor (NowPlayingSnapshot?) -> Void)?
    private var tokens: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    func start(update: @escaping @MainActor (NowPlayingSnapshot?) -> Void, failure: @escaping @MainActor () -> Void) {
        guard bridge.isAvailable else { failure(); return }
        self.update = update
        bridge.register()
        for name in NowPlayingMediaRemoteBridge.notificationNames {
            let token = NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil,
                                                               queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
            tokens.append(token)
        }
        refresh()
        // Safety net: some players stop posting notifications; re-read slowly.
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens.removeAll()
        refreshTask?.cancel()
        pollTask?.cancel()
        bridge.unregister()
        update = nil
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func refresh() {
        bridge.fetchSnapshot { [weak self] snapshot in
            self?.update?(snapshot)
        }
    }

    func perform(_ command: NowPlayingRemoteCommand) {
        bridge.send(command)
    }

    func setLockScreenWidgetVisible(_ visible: Bool) {}
}
