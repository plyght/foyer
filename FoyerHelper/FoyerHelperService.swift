import Foundation

/// Allowed classes for the dictionaries and arrays exchanged over NSXPC.
enum HelperXPCInterfaces {
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

/// The exported object of FoyerHelper.xpc (one per connection).
final class FoyerHelperService: NSObject, FoyerHelperProtocol {
    private weak var connection: NSXPCConnection?
    private let mediaRemote = HelperMediaRemote.shared
    private let observer = HelperNowPlayingObserver.shared
    private let lock = NSLock()
    private var isObserving = false

    init(connection: NSXPCConnection) {
        self.connection = connection
        super.init()
    }

    func connectionDidInvalidate() {
        stopNowPlayingObservation()
    }

    private var client: FoyerHelperClientProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { _ in } as? FoyerHelperClientProtocol
    }

    // MARK: Transport

    func playPause() {
        mediaRemote.send(.togglePlayPause)
    }

    func previousTrack() {
        mediaRemote.send(.previousTrack)
    }

    func nextTrack() {
        mediaRemote.send(.nextTrack)
    }

    func getSeekerPosition(_ reply: @escaping (Double) -> Void) {
        mediaRemote.nowPlayingInfo(on: observer.queue) { info in
            guard let info else { reply(0); return }
            let elapsed = (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
            let rate = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0
            let duration = (info["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0
            var position = elapsed
            if let timestamp = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date, rate > 0 {
                position += Date().timeIntervalSince(timestamp) * rate
            }
            if duration > 0 { position = min(position, duration) }
            reply(max(0, position))
        }
    }

    func setPlayerPosition(_ position: Double) {
        mediaRemote.setElapsedTime(position)
    }

    func setPlaybackRate(_ rate: Double) {
        mediaRemote.setPlaybackRate(rate)
    }

    func setShuffleMode(_ mode: Int) {
        mediaRemote.setShuffleMode(mode)
    }

    func setRepeatMode(_ mode: Int) {
        mediaRemote.setRepeatMode(mode)
    }

    // MARK: State

    func getIsPlaying(_ reply: @escaping (Bool) -> Void) {
        mediaRemote.isPlaying(on: observer.queue) { reply($0) }
    }

    func getNowPlayingInfo(_ reply: @escaping ([String: Any]?) -> Void) {
        observer.snapshot { info, _, _ in reply(info) }
    }

    func getNowPlayingInfo(forBundleIdentifier bundleIdentifier: String, reply: @escaping ([String: Any]?) -> Void) {
        observer.snapshot { info, _, _ in
            guard let info, Self.info(info, matches: bundleIdentifier) else { reply(nil); return }
            reply(info)
        }
    }

    func getNowPlayingSource(_ reply: @escaping ([String: Any]?) -> Void) {
        observer.snapshot { info, _, _ in
            guard let info else { reply(nil); return }
            let keys = [
                HelperNowPlayingKey.sourceBundleIdentifier,
                HelperNowPlayingKey.sourceClientBundleIdentifier,
                HelperNowPlayingKey.sourceParentBundleIdentifier,
                HelperNowPlayingKey.sourceDisplayName,
                HelperNowPlayingKey.sourceProcessIdentifier,
            ]
            var source: [String: Any] = [:]
            for key in keys {
                if let value = info[key] { source[key] = value }
            }
            reply(source.isEmpty ? nil : source)
        }
    }

    func getNowPlayingBundle(_ reply: @escaping (String?) -> Void) {
        mediaRemote.client(on: observer.queue) { client in
            reply(client?.parentBundleIdentifier ?? client?.bundleIdentifier)
        }
    }

    func checkSupportedCommands(_ reply: @escaping ([NSNumber]) -> Void) {
        mediaRemote.supportedCommands(on: observer.queue) { reply($0) }
    }

    func checkSupportedCommands(forBundleIdentifier bundleIdentifier: String, reply: @escaping ([NSNumber]) -> Void) {
        let mediaRemote = self.mediaRemote
        let queue = observer.queue
        mediaRemote.client(on: queue) { client in
            let matches = client?.bundleIdentifier == bundleIdentifier
                || client?.parentBundleIdentifier == bundleIdentifier
            guard matches else { reply([]); return }
            mediaRemote.supportedCommands(on: queue) { reply($0) }
        }
    }

    private static func info(_ info: [String: Any], matches bundleIdentifier: String) -> Bool {
        let candidates = [
            info[HelperNowPlayingKey.sourceBundleIdentifier] as? String,
            info[HelperNowPlayingKey.sourceClientBundleIdentifier] as? String,
            info[HelperNowPlayingKey.sourceParentBundleIdentifier] as? String,
        ]
        return candidates.contains { $0 == bundleIdentifier }
    }

    // MARK: Observation

    func startNowPlayingObservation() {
        lock.lock()
        let alreadyObserving = isObserving
        isObserving = true
        lock.unlock()
        guard !alreadyObserving else { return }

        observer.subscribe(self) { [weak self] update in
            guard let self, let client = self.client else { return }
            if update.infoChanged || update.isPlayingChanged {
                client.nowPlayingDidChange(update.info)
            }
            if update.isPlayingChanged {
                client.isPlayingDidChange(update.isPlaying)
            }
            if update.bundleChanged {
                client.nowPlayingApplicationDidChange(update.bundleIdentifier)
            }
        }
    }

    func stopNowPlayingObservation() {
        lock.lock()
        let wasObserving = isObserving
        isObserving = false
        lock.unlock()
        guard wasObserving else { return }
        observer.unsubscribe(self)
    }

    func postLockScreenWidgetIsShown() {
        observer.setLockScreenWidgetVisible(true)
    }

    func postLockScreenWidgetIsHidden() {
        observer.setLockScreenWidgetVisible(false)
    }

    // MARK: Updates

    func installUpdate(withZipPath zipPath: String, appBundlePath: String, reply: @escaping (Bool, String?) -> Void) {
        let pid = connection?.processIdentifier ?? 0
        HelperUpdateInstaller.install(zipPath: zipPath, appBundlePath: appBundlePath, appPID: pid, reply: reply)
    }
}
