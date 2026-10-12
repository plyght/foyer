import Foundation

/// Where a snapshot came from.
enum NowPlayingOrigin: Equatable {
    case mediaRemote
    case music
    case spotify
}

/// MediaRemote shuffle modes (`kMRMediaRemoteNowPlayingInfoShuffleMode`).
enum NowPlayingShuffleMode: Int {
    case unknown = 0, off = 1, albums = 2, songs = 3
    var isOn: Bool { self == .albums || self == .songs }
}

/// MediaRemote repeat modes (`kMRMediaRemoteNowPlayingInfoRepeatMode`).
enum NowPlayingRepeatMode: Int {
    case unknown = 0, off = 1, one = 2, all = 3
    var isOn: Bool { self == .one || self == .all }

    /// Music's extra-button cycle: off → all → one → off (Part C2 §3.3).
    var next: NowPlayingRepeatMode {
        switch self {
        case .off, .unknown: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

/// Commands routed to whichever backend owns the current item.
enum NowPlayingRemoteCommand: Equatable {
    case togglePlayPause
    case next
    case previous
    case seek(Double)
    case setShuffle(NowPlayingShuffleMode)
    case setRepeat(NowPlayingRepeatMode)
}

/// One immutable reading of the now-playing state.
struct NowPlayingSnapshot: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var artworkData: Data?
    /// Remote artwork (Spotify's AppleScript only exposes a URL).
    var artworkURL: URL?
    var duration: Double = 0
    var elapsed: Double = 0
    /// When `elapsed` was sampled.
    var timestamp: Date = Date()
    var playbackRate: Double = 0
    var isPlaying = false
    var isExplicit = false
    var shuffleMode: NowPlayingShuffleMode = .unknown
    var repeatMode: NowPlayingRepeatMode = .unknown
    var isFavorite: Bool?
    var contentIdentifier: String?
    var bundleIdentifier: String?
    var parentBundleIdentifier: String?
    var displayName: String?
    var processIdentifier: pid_t?
    /// Spotify's `spotify url` (spotify:track:…).
    var shareURI: String?
    var origin: NowPlayingOrigin = .mediaRemote

    /// Identity used for "the song changed" (Quick Peek, flips, crossfades).
    var trackIdentity: String {
        "\(title)\u{1F}\(artist)\u{1F}\(album)"
    }

    var hasContent: Bool {
        !title.isEmpty || artworkData != nil || artworkURL != nil || duration > 0
    }

    /// The app the user thinks of as the source (Safari for a web player).
    var sourceAppBundleIdentifier: String? {
        parentBundleIdentifier ?? bundleIdentifier
    }

    /// Elapsed time extrapolated from the sample timestamp and rate.
    func elapsed(at date: Date) -> Double {
        var value = elapsed
        if isPlaying {
            let rate = playbackRate > 0 ? playbackRate : 1
            value += date.timeIntervalSince(timestamp) * rate
        }
        if duration > 0 { value = min(value, duration) }
        return max(0, value)
    }

    /// Builds a snapshot from a `HelperNowPlayingKey` dictionary (helper or
    /// in-process MediaRemote).
    init?(helperInfo info: [String: Any]?) {
        guard let info else { return nil }
        func string(_ key: String) -> String? { info[key] as? String }
        func double(_ key: String) -> Double? { (info[key] as? NSNumber)?.doubleValue }
        func bool(_ key: String) -> Bool? { (info[key] as? NSNumber)?.boolValue }
        func int(_ key: String) -> Int? { (info[key] as? NSNumber)?.intValue }

        title = string(HelperNowPlayingKey.title) ?? ""
        artist = string(HelperNowPlayingKey.artist) ?? ""
        album = string(HelperNowPlayingKey.album) ?? ""
        artworkData = info[HelperNowPlayingKey.artworkData] as? Data
        duration = max(0, double(HelperNowPlayingKey.duration) ?? 0)
        elapsed = max(0, double(HelperNowPlayingKey.elapsedTime) ?? 0)
        timestamp = (info[HelperNowPlayingKey.timestamp] as? Date) ?? Date()
        playbackRate = double(HelperNowPlayingKey.playbackRate) ?? 0
        isPlaying = bool(HelperNowPlayingKey.isPlaying) ?? (playbackRate > 0)
        isExplicit = bool(HelperNowPlayingKey.isExplicit) ?? false
        shuffleMode = NowPlayingShuffleMode(rawValue: int(HelperNowPlayingKey.shuffleMode) ?? 0) ?? .unknown
        repeatMode = NowPlayingRepeatMode(rawValue: int(HelperNowPlayingKey.repeatMode) ?? 0) ?? .unknown
        contentIdentifier = string(HelperNowPlayingKey.contentItemIdentifier)
        bundleIdentifier = string(HelperNowPlayingKey.sourceBundleIdentifier)
            ?? string(HelperNowPlayingKey.sourceClientBundleIdentifier)
        parentBundleIdentifier = string(HelperNowPlayingKey.sourceParentBundleIdentifier)
        displayName = string(HelperNowPlayingKey.sourceDisplayName)
        if let pid = int(HelperNowPlayingKey.sourceProcessIdentifier), pid > 0 {
            processIdentifier = pid_t(pid)
        }
        origin = .mediaRemote
        guard hasContent || bundleIdentifier != nil else { return nil }
    }

    init() {}
}

/// Bundle identifiers Foyer knows how to script.
enum NowPlayingBundleID {
    static let music = "com.apple.Music"
    static let spotify = "com.spotify.client"
    static let safari = "com.apple.Safari"
    static let webKitGPU = "com.apple.WebKit.GPU"
}
