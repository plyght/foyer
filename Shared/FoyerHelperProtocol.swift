import Foundation

/// NSXPC interface of FoyerHelper.xpc (mirrors AlcoveHelper, Part A §6).
/// The helper's bundle id is `com.apple.controlcenter.FoyerHelper`, which lets
/// MediaRemote answer it on macOS 15.4+.
@objc public protocol FoyerHelperProtocol {
    // MARK: Now Playing (MediaRemote)
    func playPause()
    func previousTrack()
    func nextTrack()
    func getSeekerPosition(_ reply: @escaping (Double) -> Void)
    func setPlayerPosition(_ position: Double)
    func setPlaybackRate(_ rate: Double)
    func setShuffleMode(_ mode: Int)
    func setRepeatMode(_ mode: Int)
    func getIsPlaying(_ reply: @escaping (Bool) -> Void)
    /// Property-list-safe now-playing dictionary (see `HelperNowPlayingKey`).
    func getNowPlayingInfo(_ reply: @escaping ([String: Any]?) -> Void)
    func getNowPlayingInfo(forBundleIdentifier bundleIdentifier: String, reply: @escaping ([String: Any]?) -> Void)
    func getNowPlayingSource(_ reply: @escaping ([String: Any]?) -> Void)
    func getNowPlayingBundle(_ reply: @escaping (String?) -> Void)
    func checkSupportedCommands(_ reply: @escaping ([NSNumber]) -> Void)
    func checkSupportedCommands(forBundleIdentifier bundleIdentifier: String, reply: @escaping ([NSNumber]) -> Void)
    func startNowPlayingObservation()
    func stopNowPlayingObservation()
    func postLockScreenWidgetIsShown()
    func postLockScreenWidgetIsHidden()

    // MARK: Updates
    /// Unzips `zipPath` with /usr/bin/ditto over `appBundlePath` and relaunches.
    func installUpdate(withZipPath zipPath: String, appBundlePath: String, reply: @escaping (Bool, String?) -> Void)
}

/// Callbacks from the helper to the app (exported object on the app side).
@objc public protocol FoyerHelperClientProtocol {
    func nowPlayingDidChange(_ info: [String: Any]?)
    func isPlayingDidChange(_ isPlaying: Bool)
    func nowPlayingApplicationDidChange(_ bundleIdentifier: String?)
}

/// Keys of the dictionaries exchanged with the helper.
public enum HelperNowPlayingKey {
    public static let title = "title"
    public static let artist = "artist"
    public static let album = "album"
    public static let artworkData = "artworkData"
    public static let artworkMIMEType = "artworkMIMEType"
    public static let duration = "duration"
    public static let elapsedTime = "elapsedTime"
    public static let timestamp = "timestamp"
    public static let playbackRate = "playbackRate"
    public static let isPlaying = "isPlaying"
    public static let isExplicit = "isExplicit"
    public static let shuffleMode = "shuffleMode"
    public static let repeatMode = "repeatMode"
    public static let contentItemIdentifier = "contentItemIdentifier"
    public static let isMusicApp = "isMusicApp"
    public static let audioTier = "audioTierKey"
    public static let audioRenderingMode = "audioRenderingModeKey"
    public static let isLossless = "isLosslessKey"
    public static let isDolbyAtmos = "isDolbyAtmosKey"
    public static let sourceBundleIdentifier = "sourceBundleIdentifierKey"
    public static let sourceClientBundleIdentifier = "sourceClientBundleIdentifierKey"
    public static let sourceParentBundleIdentifier = "sourceParentBundleIdentifierKey"
    public static let sourceDisplayName = "sourceDisplayNameKey"
    public static let sourceProcessIdentifier = "sourceProcessIdentifierKey"
}

public enum FoyerHelperConstants {
    public static let serviceName = "com.apple.controlcenter.FoyerHelper"
}
