import Foundation

/// MediaRemote bridge used inside FoyerHelper.xpc. Every symbol is resolved at
/// runtime with dlopen/dlsym (the private framework is never linked), and every
/// call degrades to a no-op / nil reply when a symbol is missing.
///
/// The helper carries the bundle id `com.apple.controlcenter.FoyerHelper`, which
/// is what lets MediaRemote answer it on macOS 15.4+ (teardown Part A §6).
final class HelperMediaRemote {
    static let shared = HelperMediaRemote()

    /// `MRMediaRemoteCommand` raw values.
    enum Command: UInt32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case stop = 3
        case nextTrack = 4
        case previousTrack = 5
        case changePlaybackRate = 19
        case likeTrack = 21
        case seekToPlaybackPosition = 24
        case changeRepeatMode = 25
        case changeShuffleMode = 26
    }

    /// Distributed through `NotificationCenter.default` once
    /// `MRMediaRemoteRegisterForNowPlayingNotifications` has been called.
    static let observedNotifications: [String] = [
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
        "kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification",
    ]

    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias UnregisterFn = @convention(c) () -> Void
    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void
    private typealias GetBoolFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias GetPIDFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
    private typealias GetClientFn = @convention(c) (DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (UInt32, NSDictionary?) -> Bool
    private typealias SetDoubleFn = @convention(c) (Double) -> Void
    private typealias SetIntFn = @convention(c) (Int32) -> Void
    private typealias ClientStringFn = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    private typealias ClientPIDFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    private typealias LocalOriginFn = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias SupportedCommandsFn = @convention(c) (UnsafeMutableRawPointer?, DispatchQueue, @escaping @convention(block) (NSArray?) -> Void) -> Void
    private typealias CommandInfoCommandFn = @convention(c) (UnsafeMutableRawPointer?) -> UInt32
    private typealias CommandInfoEnabledFn = @convention(c) (UnsafeMutableRawPointer?) -> Bool

    private let handle: UnsafeMutableRawPointer?

    private let registerFn: RegisterFn?
    private let unregisterFn: UnregisterFn?
    private let getInfoFn: GetInfoFn?
    private let getIsPlayingFn: GetBoolFn?
    private let getPIDFn: GetPIDFn?
    private let getClientFn: GetClientFn?
    private let sendCommandFn: SendCommandFn?
    private let setElapsedTimeFn: SetDoubleFn?
    private let setShuffleModeFn: SetIntFn?
    private let setRepeatModeFn: SetIntFn?
    private let clientBundleFn: ClientStringFn?
    private let clientParentBundleFn: ClientStringFn?
    private let clientDisplayNameFn: ClientStringFn?
    private let clientPIDFn: ClientPIDFn?
    private let localOriginFn: LocalOriginFn?
    private let supportedCommandsFn: SupportedCommandsFn?
    private let commandInfoCommandFn: CommandInfoCommandFn?
    private let commandInfoEnabledFn: CommandInfoEnabledFn?

    private init() {
        let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
        handle = h

        func load<T>(_ name: String, _ type: T.Type) -> T? {
            guard let h, let sym = dlsym(h, name) else { return nil }
            return unsafeBitCast(sym, to: type)
        }

        registerFn = load("MRMediaRemoteRegisterForNowPlayingNotifications", RegisterFn.self)
        unregisterFn = load("MRMediaRemoteUnregisterForNowPlayingNotifications", UnregisterFn.self)
        getInfoFn = load("MRMediaRemoteGetNowPlayingInfo", GetInfoFn.self)
        getIsPlayingFn = load("MRMediaRemoteGetNowPlayingApplicationIsPlaying", GetBoolFn.self)
        getPIDFn = load("MRMediaRemoteGetNowPlayingApplicationPID", GetPIDFn.self)
        getClientFn = load("MRMediaRemoteGetNowPlayingClient", GetClientFn.self)
        sendCommandFn = load("MRMediaRemoteSendCommand", SendCommandFn.self)
        setElapsedTimeFn = load("MRMediaRemoteSetElapsedTime", SetDoubleFn.self)
        setShuffleModeFn = load("MRMediaRemoteSetShuffleMode", SetIntFn.self)
        setRepeatModeFn = load("MRMediaRemoteSetRepeatMode", SetIntFn.self)
        clientBundleFn = load("MRNowPlayingClientGetBundleIdentifier", ClientStringFn.self)
        clientParentBundleFn = load("MRNowPlayingClientGetParentAppBundleIdentifier", ClientStringFn.self)
        clientDisplayNameFn = load("MRNowPlayingClientGetDisplayName", ClientStringFn.self)
        clientPIDFn = load("MRNowPlayingClientGetProcessIdentifier", ClientPIDFn.self)
        localOriginFn = load("MRMediaRemoteGetLocalOrigin", LocalOriginFn.self)
        supportedCommandsFn = load("MRMediaRemoteGetSupportedCommandsForOrigin", SupportedCommandsFn.self)
        commandInfoCommandFn = load("MRMediaRemoteCommandInfoGetCommand", CommandInfoCommandFn.self)
        commandInfoEnabledFn = load("MRMediaRemoteCommandInfoGetEnabled", CommandInfoEnabledFn.self)
    }

    var isAvailable: Bool { getInfoFn != nil }

    // MARK: Notifications

    func register(on queue: DispatchQueue) {
        registerFn?(queue)
    }

    func unregister() {
        unregisterFn?()
    }

    // MARK: Reads (each completion is called exactly once on `queue`)

    func nowPlayingInfo(on queue: DispatchQueue, _ completion: @escaping (NSDictionary?) -> Void) {
        guard let getInfoFn else { queue.async { completion(nil) }; return }
        let once = HelperOnce(queue: queue, timeout: 2) { (value: NSDictionary?) in completion(value) }
        getInfoFn(queue) { info in once.fire(info) }
    }

    func isPlaying(on queue: DispatchQueue, _ completion: @escaping (Bool) -> Void) {
        guard let getIsPlayingFn else { queue.async { completion(false) }; return }
        let once = HelperOnce(queue: queue, timeout: 2, fallback: false) { (value: Bool) in completion(value) }
        getIsPlayingFn(queue) { playing in once.fire(playing) }
    }

    func applicationPID(on queue: DispatchQueue, _ completion: @escaping (Int32) -> Void) {
        guard let getPIDFn else { queue.async { completion(0) }; return }
        let once = HelperOnce(queue: queue, timeout: 2, fallback: Int32(0)) { (value: Int32) in completion(value) }
        getPIDFn(queue) { pid in once.fire(pid) }
    }

    struct ClientInfo {
        var bundleIdentifier: String?
        var parentBundleIdentifier: String?
        var displayName: String?
        var processIdentifier: Int32
    }

    func client(on queue: DispatchQueue, _ completion: @escaping (ClientInfo?) -> Void) {
        guard let getClientFn else { queue.async { completion(nil) }; return }
        let once = HelperOnce(queue: queue, timeout: 2) { (value: ClientInfo?) in completion(value) }
        getClientFn(queue) { [weak self] client in
            guard let self, let client else { once.fire(nil); return }
            once.fire(self.describe(client: client))
        }
    }

    private func describe(client: AnyObject) -> ClientInfo {
        let pointer = Unmanaged.passUnretained(client).toOpaque()

        func string(_ fn: ClientStringFn?, kvcKey: String) -> String? {
            if let fn, let raw = fn(pointer) {
                let value = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
                return value.isEmpty ? nil : value
            }
            if let object = client as? NSObject, object.responds(to: NSSelectorFromString(kvcKey)) {
                return object.value(forKey: kvcKey) as? String
            }
            return nil
        }

        var pid: Int32 = 0
        if let clientPIDFn {
            pid = clientPIDFn(pointer)
        } else if let object = client as? NSObject, object.responds(to: NSSelectorFromString("processIdentifier")) {
            pid = (object.value(forKey: "processIdentifier") as? NSNumber)?.int32Value ?? 0
        }

        return ClientInfo(
            bundleIdentifier: string(clientBundleFn, kvcKey: "bundleIdentifier"),
            parentBundleIdentifier: string(clientParentBundleFn, kvcKey: "parentApplicationBundleIdentifier"),
            displayName: string(clientDisplayNameFn, kvcKey: "displayName"),
            processIdentifier: pid)
    }

    func supportedCommands(on queue: DispatchQueue, _ completion: @escaping ([NSNumber]) -> Void) {
        guard let supportedCommandsFn, let commandInfoCommandFn else {
            queue.async { completion([]) }
            return
        }
        let origin = localOriginFn?()
        let enabledFn = commandInfoEnabledFn
        let once = HelperOnce(queue: queue, timeout: 2, fallback: [NSNumber]()) { (value: [NSNumber]) in completion(value) }
        supportedCommandsFn(origin, queue) { array in
            guard let array else { once.fire([]); return }
            var result: [NSNumber] = []
            for item in array {
                let object = item as AnyObject
                let pointer = Unmanaged.passUnretained(object).toOpaque()
                if let enabledFn, !enabledFn(pointer) { continue }
                result.append(NSNumber(value: commandInfoCommandFn(pointer)))
            }
            once.fire(result)
        }
    }

    // MARK: Commands

    @discardableResult
    func send(_ command: Command, options: [String: Any]? = nil) -> Bool {
        guard let sendCommandFn else { return false }
        return sendCommandFn(command.rawValue, options.map { $0 as NSDictionary })
    }

    func setElapsedTime(_ seconds: Double) {
        if let setElapsedTimeFn {
            setElapsedTimeFn(max(0, seconds))
        } else {
            send(.seekToPlaybackPosition, options: ["kMRMediaRemoteOptionPlaybackPosition": max(0, seconds)])
        }
    }

    func setShuffleMode(_ mode: Int) {
        if let setShuffleModeFn {
            setShuffleModeFn(Int32(mode))
        } else {
            send(.changeShuffleMode, options: ["kMRMediaRemoteOptionShuffleMode": mode])
        }
    }

    func setRepeatMode(_ mode: Int) {
        if let setRepeatModeFn {
            setRepeatModeFn(Int32(mode))
        } else {
            send(.changeRepeatMode, options: ["kMRMediaRemoteOptionRepeatMode": mode])
        }
    }

    func setPlaybackRate(_ rate: Double) {
        send(.changePlaybackRate, options: ["kMRMediaRemoteOptionPlaybackRate": rate])
    }

    // MARK: Dictionary conversion

    /// Converts a raw MediaRemote now-playing dictionary into the
    /// property-list-safe dictionary of `HelperNowPlayingKey` keys.
    static func sanitize(info: NSDictionary?, isPlaying: Bool, client: ClientInfo?, pid: Int32) -> [String: Any]? {
        var out: [String: Any] = [:]

        if let info {
            func copy(_ mrKey: String, to key: String) {
                guard let value = info[mrKey], let safe = plistSafe(value) else { return }
                out[key] = safe
            }
            copy("kMRMediaRemoteNowPlayingInfoTitle", to: HelperNowPlayingKey.title)
            copy("kMRMediaRemoteNowPlayingInfoArtist", to: HelperNowPlayingKey.artist)
            copy("kMRMediaRemoteNowPlayingInfoAlbum", to: HelperNowPlayingKey.album)
            copy("kMRMediaRemoteNowPlayingInfoArtworkData", to: HelperNowPlayingKey.artworkData)
            copy("kMRMediaRemoteNowPlayingInfoArtworkMIMEType", to: HelperNowPlayingKey.artworkMIMEType)
            copy("kMRMediaRemoteNowPlayingInfoDuration", to: HelperNowPlayingKey.duration)
            copy("kMRMediaRemoteNowPlayingInfoElapsedTime", to: HelperNowPlayingKey.elapsedTime)
            copy("kMRMediaRemoteNowPlayingInfoTimestamp", to: HelperNowPlayingKey.timestamp)
            copy("kMRMediaRemoteNowPlayingInfoPlaybackRate", to: HelperNowPlayingKey.playbackRate)
            copy("kMRMediaRemoteNowPlayingInfoIsExplicitTrack", to: HelperNowPlayingKey.isExplicit)
            copy("kMRMediaRemoteNowPlayingInfoShuffleMode", to: HelperNowPlayingKey.shuffleMode)
            copy("kMRMediaRemoteNowPlayingInfoRepeatMode", to: HelperNowPlayingKey.repeatMode)
            copy("kMRMediaRemoteNowPlayingInfoContentItemIdentifier", to: HelperNowPlayingKey.contentItemIdentifier)
            copy("kMRMediaRemoteNowPlayingInfoIsMusicApp", to: HelperNowPlayingKey.isMusicApp)

            // Audio format extras are published under keys that vary between
            // releases; pick them up by name.
            for (rawKey, value) in info {
                guard let key = rawKey as? String else { continue }
                if key.localizedCaseInsensitiveContains("Lossless"), let number = value as? NSNumber {
                    out[HelperNowPlayingKey.isLossless] = number.boolValue
                } else if key.localizedCaseInsensitiveContains("DolbyAtmos"), let number = value as? NSNumber {
                    out[HelperNowPlayingKey.isDolbyAtmos] = number.boolValue
                } else if key.localizedCaseInsensitiveContains("AudioRenderingMode"), let safe = plistSafe(value) {
                    out[HelperNowPlayingKey.audioRenderingMode] = safe
                } else if key.localizedCaseInsensitiveContains("AudioTier"), let safe = plistSafe(value) {
                    out[HelperNowPlayingKey.audioTier] = safe
                }
            }
        }

        if let client {
            if let bundle = client.bundleIdentifier {
                out[HelperNowPlayingKey.sourceBundleIdentifier] = bundle
                out[HelperNowPlayingKey.sourceClientBundleIdentifier] = bundle
            }
            if let parent = client.parentBundleIdentifier {
                out[HelperNowPlayingKey.sourceParentBundleIdentifier] = parent
            }
            if let name = client.displayName {
                out[HelperNowPlayingKey.sourceDisplayName] = name
            }
        }
        let resolvedPID = (client?.processIdentifier ?? 0) > 0 ? (client?.processIdentifier ?? 0) : pid
        if resolvedPID > 0 {
            out[HelperNowPlayingKey.sourceProcessIdentifier] = NSNumber(value: resolvedPID)
        }

        let hasContent = out[HelperNowPlayingKey.title] != nil
            || out[HelperNowPlayingKey.artworkData] != nil
            || out[HelperNowPlayingKey.duration] != nil
            || out[HelperNowPlayingKey.sourceBundleIdentifier] != nil
        guard hasContent else { return nil }

        out[HelperNowPlayingKey.isPlaying] = isPlaying
        return out
    }

    /// Only NSString / NSNumber / NSData / NSDate survive.
    static func plistSafe(_ value: Any) -> Any? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number }
        if let data = value as? Data { return data }
        if let date = value as? Date { return date }
        return nil
    }
}

/// Calls `body` exactly once: with the first fired value, or with `fallback`
/// after `timeout` seconds if MediaRemote never answers (it does not call back
/// for clients it refuses).
final class HelperOnce<Value> {
    private let lock = NSLock()
    private var done = false
    private let body: (Value) -> Void
    private let queue: DispatchQueue

    init(queue: DispatchQueue, timeout: TimeInterval, fallback: Value, body: @escaping (Value) -> Void) {
        self.queue = queue
        self.body = body
        // Strong capture on purpose: MediaRemote may drop the reply block
        // without calling it, and the timeout must still deliver the fallback.
        queue.asyncAfter(deadline: .now() + timeout) {
            self.fire(fallback)
        }
    }

    func fire(_ value: Value) {
        lock.lock()
        if done { lock.unlock(); return }
        done = true
        lock.unlock()
        body(value)
    }
}

extension HelperOnce where Value: ExpressibleByNilLiteral {
    convenience init(queue: DispatchQueue, timeout: TimeInterval, body: @escaping (Value) -> Void) {
        self.init(queue: queue, timeout: timeout, fallback: nil, body: body)
    }
}
