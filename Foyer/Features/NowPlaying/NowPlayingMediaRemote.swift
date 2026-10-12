import AppKit
import Foundation

/// In-process MediaRemote access (fallback when FoyerHelper.xpc is
/// unavailable). On macOS 15.4+ MediaRemote may refuse non-Apple clients, which
/// is why the helper is preferred. All symbols go through `PrivateAPI`.
@MainActor
final class NowPlayingMediaRemoteBridge {
    static let shared = NowPlayingMediaRemoteBridge()

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

    static let notificationNames: [String] = [
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
    ]

    private init() {
        let path = PrivateAPI.mediaRemote
        registerFn = PrivateAPI.symbol("MRMediaRemoteRegisterForNowPlayingNotifications", in: path, as: RegisterFn.self)
        unregisterFn = PrivateAPI.symbol("MRMediaRemoteUnregisterForNowPlayingNotifications", in: path, as: UnregisterFn.self)
        getInfoFn = PrivateAPI.symbol("MRMediaRemoteGetNowPlayingInfo", in: path, as: GetInfoFn.self)
        getIsPlayingFn = PrivateAPI.symbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying", in: path, as: GetBoolFn.self)
        getPIDFn = PrivateAPI.symbol("MRMediaRemoteGetNowPlayingApplicationPID", in: path, as: GetPIDFn.self)
        getClientFn = PrivateAPI.symbol("MRMediaRemoteGetNowPlayingClient", in: path, as: GetClientFn.self)
        sendCommandFn = PrivateAPI.symbol("MRMediaRemoteSendCommand", in: path, as: SendCommandFn.self)
        setElapsedTimeFn = PrivateAPI.symbol("MRMediaRemoteSetElapsedTime", in: path, as: SetDoubleFn.self)
        setShuffleModeFn = PrivateAPI.symbol("MRMediaRemoteSetShuffleMode", in: path, as: SetIntFn.self)
        setRepeatModeFn = PrivateAPI.symbol("MRMediaRemoteSetRepeatMode", in: path, as: SetIntFn.self)
        clientBundleFn = PrivateAPI.symbol("MRNowPlayingClientGetBundleIdentifier", in: path, as: ClientStringFn.self)
        clientParentBundleFn = PrivateAPI.symbol("MRNowPlayingClientGetParentAppBundleIdentifier", in: path, as: ClientStringFn.self)
        clientDisplayNameFn = PrivateAPI.symbol("MRNowPlayingClientGetDisplayName", in: path, as: ClientStringFn.self)
    }

    var isAvailable: Bool { getInfoFn != nil && sendCommandFn != nil }

    func register() { registerFn?(DispatchQueue.main) }
    func unregister() { unregisterFn?() }

    /// Reads info, playing state, client and PID; calls back on the main actor.
    func fetchSnapshot(_ completion: @escaping @MainActor (NowPlayingSnapshot?) -> Void) {
        guard let getInfoFn else { completion(nil); return }
        let queue = DispatchQueue.main
        let group = DispatchGroup()
        let box = NowPlayingFetchBox()

        // MediaRemote never answers refused clients; give up after 2 s.
        let gate = NowPlayingCallbackGate()

        group.enter()
        getInfoFn(queue) { dictionary in
            box.info = dictionary as? [String: Any]
            group.leave()
        }
        if let getIsPlayingFn {
            group.enter()
            getIsPlayingFn(queue) { value in box.isPlaying = value; group.leave() }
        }
        if let getPIDFn {
            group.enter()
            getPIDFn(queue) { value in box.pid = value; group.leave() }
        }
        if let getClientFn {
            let bundleFn = clientBundleFn
            let parentFn = clientParentBundleFn
            let nameFn = clientDisplayNameFn
            group.enter()
            getClientFn(queue) { client in
                if let client {
                    let pointer = Unmanaged.passUnretained(client).toOpaque()
                    box.bundle = Self.string(bundleFn, pointer)
                    box.parent = Self.string(parentFn, pointer)
                    box.displayName = Self.string(nameFn, pointer)
                }
                group.leave()
            }
        }

        group.notify(queue: queue) {
            guard gate.open() else { return }
            let dictionary = Self.sanitize(info: box.info, isPlaying: box.isPlaying, bundle: box.bundle,
                                           parent: box.parent, displayName: box.displayName, pid: box.pid)
            let snapshot = NowPlayingSnapshot(helperInfo: dictionary)
            MainActor.assumeIsolated {
                completion(snapshot)
            }
        }
        queue.asyncAfter(deadline: .now() + 2) {
            guard gate.open() else { return }
            MainActor.assumeIsolated { completion(nil) }
        }
    }

    nonisolated private static func string(_ fn: ClientStringFn?, _ pointer: UnsafeMutableRawPointer) -> String? {
        guard let fn, let raw = fn(pointer) else { return nil }
        let value = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        return value.isEmpty ? nil : value
    }

    @discardableResult
    func send(_ command: NowPlayingRemoteCommand) -> Bool {
        switch command {
        case .togglePlayPause: return sendRaw(2)
        case .next: return sendRaw(4)
        case .previous: return sendRaw(5)
        case .seek(let position):
            if let setElapsedTimeFn { setElapsedTimeFn(max(0, position)); return true }
            return sendRaw(24, options: ["kMRMediaRemoteOptionPlaybackPosition": max(0, position)])
        case .setShuffle(let mode):
            if let setShuffleModeFn { setShuffleModeFn(Int32(mode.rawValue)); return true }
            return sendRaw(26, options: ["kMRMediaRemoteOptionShuffleMode": mode.rawValue])
        case .setRepeat(let mode):
            if let setRepeatModeFn { setRepeatModeFn(Int32(mode.rawValue)); return true }
            return sendRaw(25, options: ["kMRMediaRemoteOptionRepeatMode": mode.rawValue])
        }
    }

    private func sendRaw(_ command: UInt32, options: [String: Any]? = nil) -> Bool {
        guard let sendCommandFn else { return false }
        return sendCommandFn(command, options.map { $0 as NSDictionary })
    }

    /// Same mapping as the helper's sanitizer, producing `HelperNowPlayingKey` keys.
    nonisolated static func sanitize(info: [String: Any]?, isPlaying: Bool, bundle: String?, parent: String?,
                                     displayName: String?, pid: Int32) -> [String: Any]? {
        var out: [String: Any] = [:]
        let mapping: [(String, String)] = [
            ("kMRMediaRemoteNowPlayingInfoTitle", HelperNowPlayingKey.title),
            ("kMRMediaRemoteNowPlayingInfoArtist", HelperNowPlayingKey.artist),
            ("kMRMediaRemoteNowPlayingInfoAlbum", HelperNowPlayingKey.album),
            ("kMRMediaRemoteNowPlayingInfoArtworkData", HelperNowPlayingKey.artworkData),
            ("kMRMediaRemoteNowPlayingInfoArtworkMIMEType", HelperNowPlayingKey.artworkMIMEType),
            ("kMRMediaRemoteNowPlayingInfoDuration", HelperNowPlayingKey.duration),
            ("kMRMediaRemoteNowPlayingInfoElapsedTime", HelperNowPlayingKey.elapsedTime),
            ("kMRMediaRemoteNowPlayingInfoTimestamp", HelperNowPlayingKey.timestamp),
            ("kMRMediaRemoteNowPlayingInfoPlaybackRate", HelperNowPlayingKey.playbackRate),
            ("kMRMediaRemoteNowPlayingInfoIsExplicitTrack", HelperNowPlayingKey.isExplicit),
            ("kMRMediaRemoteNowPlayingInfoShuffleMode", HelperNowPlayingKey.shuffleMode),
            ("kMRMediaRemoteNowPlayingInfoRepeatMode", HelperNowPlayingKey.repeatMode),
            ("kMRMediaRemoteNowPlayingInfoContentItemIdentifier", HelperNowPlayingKey.contentItemIdentifier),
            ("kMRMediaRemoteNowPlayingInfoIsMusicApp", HelperNowPlayingKey.isMusicApp),
        ]
        if let info {
            for (mrKey, key) in mapping {
                guard let value = info[mrKey] else { continue }
                if let string = value as? String { out[key] = string }
                else if let number = value as? NSNumber { out[key] = number }
                else if let data = value as? Data { out[key] = data }
                else if let date = value as? Date { out[key] = date }
            }
        }
        if let bundle {
            out[HelperNowPlayingKey.sourceBundleIdentifier] = bundle
            out[HelperNowPlayingKey.sourceClientBundleIdentifier] = bundle
        }
        if let parent { out[HelperNowPlayingKey.sourceParentBundleIdentifier] = parent }
        if let displayName { out[HelperNowPlayingKey.sourceDisplayName] = displayName }
        if pid > 0 { out[HelperNowPlayingKey.sourceProcessIdentifier] = NSNumber(value: pid) }

        var playing = isPlaying
        if !playing, let rate = out[HelperNowPlayingKey.playbackRate] as? NSNumber, rate.doubleValue > 0 {
            playing = true
        }
        let hasContent = out[HelperNowPlayingKey.title] != nil || out[HelperNowPlayingKey.artworkData] != nil
            || out[HelperNowPlayingKey.duration] != nil || bundle != nil
        guard hasContent else { return nil }
        out[HelperNowPlayingKey.isPlaying] = playing
        return out
    }
}

/// Collects the racing MediaRemote replies of one fetch.
final class NowPlayingFetchBox {
    var info: [String: Any]?
    var isPlaying = false
    var pid: Int32 = 0
    var bundle: String?
    var parent: String?
    var displayName: String?
}

/// Lets exactly one of several racing callbacks through.
final class NowPlayingCallbackGate {
    private let lock = NSLock()
    private var isOpen = true

    func open() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isOpen else { return false }
        isOpen = false
        return true
    }
}
