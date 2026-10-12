import AppKit
import Combine
import Defaults
import SwiftUI

/// Owns the now-playing state and its presentation in the island:
/// - sources: FoyerHelper.xpc (MediaRemote) → in-process MediaRemote →
///   Music/Spotify AppleScript, chosen by `musicApp` / `automaticMusicApp`;
/// - lifecycle (Part C §2.1, §2.5): play → compact activity (wings 41 pt),
///   pause → 250 ms content fade, `idleDuration` hold, then the activity is
///   removed (≈467 ms shrink);
/// - Quick Peek on song change, hide while the source app is frontmost,
///   media gestures, extra-button actions and the lock-screen hooks.
@MainActor
final class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()

    // MARK: Published state

    @Published private(set) var snapshot: NowPlayingSnapshot?
    @Published private(set) var isPlaying = false
    @Published private(set) var artworkImage: NSImage?
    /// Bumped only when the artwork itself changes (drives the flip).
    @Published private(set) var artworkIdentity = 0
    @Published private(set) var palette: NowPlayingPalette = .empty
    /// Compact artwork/waveform visibility (fades 250 ms on pause).
    @Published private(set) var contentVisible = false
    @Published private(set) var shuffleMode: NowPlayingShuffleMode = .unknown
    @Published private(set) var repeatMode: NowPlayingRepeatMode = .unknown
    @Published private(set) var isFavorite = false
    /// The output/volume row under the expanded transport (Part C2 §3.3).
    @Published private(set) var isVolumeRowVisible = false
    /// Set briefly after "Copy Link" succeeds (button shows a checkmark).
    @Published private(set) var didCopyLink = false
    /// Name of the MediaRemote backend in use ("FoyerHelper", "MediaRemote" or "AppleScript").
    @Published private(set) var backendName = "None"

    // MARK: Private state

    private var backend: NowPlayingRemoteBackend?
    private var mediaRemoteSnapshot: NowPlayingSnapshot?
    private let scriptSource = NowPlayingAppleScriptSource()
    private var scriptSnapshot: NowPlayingSnapshot?
    /// Favorite/shuffle/repeat read from Music/Spotify while MediaRemote is the source.
    private var scriptExtras: NowPlayingSnapshot?

    private var started = false
    /// No Quick Peek for whatever is already playing when Foyer launches.
    private var peeksAllowedAfter = Date.distantFuture
    private var sessionActive = false
    private var sourceGone = false
    private var hiddenBySource = false
    private var lockWidgetVisible = false
    private var lastPeekedIdentity: String?
    private var artworkFingerprint: String?
    private var artworkTrackIdentity: String?
    private var artworkGeneration = 0

    private var idleTask: Task<Void, Never>?
    private var pageRemovalTask: Task<Void, Never>?
    private var extrasTask: Task<Void, Never>?
    private var copyFeedbackTask: Task<Void, Never>?
    private var pendingShuffle: (mode: NowPlayingShuffleMode, until: Date)?
    private var pendingRepeat: (mode: NowPlayingRepeatMode, until: Date)?
    private var pendingFavorite: (value: Bool, until: Date)?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        peeksAllowedAfter = Date().addingTimeInterval(4)

        scriptSource.onUpdate = { [weak self] snapshot in
            self?.scriptSnapshot = snapshot
            self?.applyEffectiveSnapshot()
        }

        NotchController.shared.mediaCommandHandler = { [weak self] command in
            self?.handle(command)
        }

        Defaults.publisher(keys: .enableNowPlaying, .musicApp, .automaticMusicApp, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.settingsChanged() }
            .store(in: &cancellables)

        Defaults.publisher(keys: .idleActivity, .idleDuration, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyLifecycle(trackChanged: false) }
            .store(in: &cancellables)

        Defaults.publisher(.hideWhileSourceIsActive, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateSourceHidden() }
            .store(in: &cancellables)

        Defaults.publisher(.controlChoice, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshExtras() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateSourceHidden() }
            .store(in: &cancellables)

        // Re-check the hardware-notch inset of the page when screens change.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.sessionActive else { return }
                self.registerPage()
            }
            .store(in: &cancellables)

        settingsChanged()
    }

    private func settingsChanged() {
        if Defaults[.enableNowPlaying] {
            if backend == nil && backendName != "AppleScript" {
                startBackend(preferHelper: true)
            }
        } else {
            backend?.stop()
            backend = nil
            backendName = "None"
            mediaRemoteSnapshot = nil
        }
        scriptSource.resetAuthorization()
        configureScriptSource()
        applyEffectiveSnapshot()
    }

    private func startBackend(preferHelper: Bool) {
        backend?.stop()
        let newBackend: NowPlayingRemoteBackend = preferHelper ? NowPlayingHelperBackend() : NowPlayingInProcessBackend()
        backend = newBackend
        backendName = newBackend.name
        newBackend.start(update: { [weak self] snapshot in
            guard let self else { return }
            self.mediaRemoteSnapshot = snapshot
            self.configureScriptSource()
            self.applyEffectiveSnapshot()
        }, failure: { [weak self] in
            self?.backendFailed(wasHelper: preferHelper)
        })
        if lockWidgetVisible {
            newBackend.setLockScreenWidgetVisible(true)
        }
    }

    private func backendFailed(wasHelper: Bool) {
        guard Defaults[.enableNowPlaying] else { return }
        if wasHelper {
            startBackend(preferHelper: false)
        } else {
            // No MediaRemote at all: Music/Spotify over AppleScript only.
            backend = nil
            backendName = "AppleScript"
            mediaRemoteSnapshot = nil
            configureScriptSource()
            applyEffectiveSnapshot()
        }
    }

    /// Music/Spotify polling runs only when it is the chosen source or the
    /// automatic fallback for a silent MediaRemote.
    private func configureScriptSource() {
        var apps: [NowPlayingAppleScriptSource.App] = []
        if Defaults[.enableNowPlaying] {
            if Defaults[.automaticMusicApp] {
                let mediaRemoteWorks = mediaRemoteSnapshot?.hasContent == true
                if !mediaRemoteWorks { apps = [.music, .spotify] }
            } else {
                switch Defaults[.musicApp] {
                case .system: apps = []
                case .music: apps = [.music]
                case .spotify: apps = [.spotify]
                }
            }
        }
        scriptSource.apps = apps
        if apps.isEmpty {
            scriptSource.stop()
            scriptSnapshot = nil
        } else {
            scriptSource.start()
        }
    }

    // MARK: Snapshot resolution

    private func resolveSnapshot() -> NowPlayingSnapshot? {
        guard Defaults[.enableNowPlaying] else { return nil }
        let mediaRemote = mediaRemoteSnapshot?.hasContent == true ? mediaRemoteSnapshot : nil

        if Defaults[.automaticMusicApp] {
            if let mediaRemote {
                if !mediaRemote.isPlaying, let script = scriptSnapshot, script.isPlaying { return script }
                return mediaRemote
            }
            return scriptSnapshot
        }

        switch Defaults[.musicApp] {
        case .system:
            return mediaRemote
        case .music, .spotify:
            let bundle = Defaults[.musicApp] == .music ? NowPlayingBundleID.music : NowPlayingBundleID.spotify
            if let mediaRemote, mediaRemote.sourceAppBundleIdentifier == bundle || mediaRemote.bundleIdentifier == bundle {
                return mediaRemote
            }
            return scriptSnapshot
        }
    }

    private func applyEffectiveSnapshot() {
        let resolved = resolveSnapshot()
        let previous = snapshot
        var next = resolved
        sourceGone = resolved == nil

        // The source vanished (app quit): keep the last item, paused, until
        // the idle timer retires it (Part B §4.4).
        if next == nil, Defaults[.enableNowPlaying], var last = previous, sessionActive {
            let now = Date()
            last.elapsed = last.elapsed(at: now)
            last.timestamp = now
            last.isPlaying = false
            next = last
        }

        let trackChanged = previous?.trackIdentity != next?.trackIdentity
        if next != previous {
            snapshot = next
        }
        let playing = next?.isPlaying ?? false
        if playing != isPlaying { isPlaying = playing }

        updateArtwork(for: next)
        if trackChanged {
            scriptExtras = nil
            refreshExtras()
        }
        updateModes()
        applyLifecycle(trackChanged: trackChanged)
        updateSourceHidden()
        NowPlayingSpectrumCenter.shared.reevaluate()
    }

    // MARK: Activity lifecycle

    /// "Now Playing" as the idle activity keeps the paused item on screen.
    private var keepsActivityWhilePaused: Bool {
        Defaults[.idleActivity] == .nowPlaying
    }

    private func applyLifecycle(trackChanged: Bool) {
        guard Defaults[.enableNowPlaying], let current = snapshot else {
            endSession()
            return
        }

        if current.isPlaying {
            idleTask?.cancel()
            idleTask = nil
            let isNewSession = !sessionActive
            if isNewSession { beginSession() }
            setContentVisible(true)
            if trackChanged || isNewSession {
                NotchController.shared.touchActivity(.nowPlaying)
                maybeShowQuickPeek(for: current)
            }
        } else if keepsActivityWhilePaused {
            idleTask?.cancel()
            idleTask = nil
            if !sessionActive { beginSession() }
            setContentVisible(true)
        } else {
            // Pause: 250 ms fade, then hold `idleDuration` before collapsing.
            setContentVisible(false)
            if sessionActive && idleTask == nil {
                let hold = max(0, Defaults[.idleDuration])
                idleTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(hold))
                    guard let self, !Task.isCancelled else { return }
                    self.idleTask = nil
                    guard !self.isPlaying else { return }
                    self.endSession()
                    if self.sourceGone {
                        self.snapshot = nil
                        self.updateArtwork(for: nil)
                    }
                }
            }
        }
    }

    private func setContentVisible(_ visible: Bool) {
        guard contentVisible != visible else { return }
        withAnimation(Constants.Animations.pauseFade) {
            contentVisible = visible
        }
    }

    private func beginSession() {
        sessionActive = true
        pageRemovalTask?.cancel()
        pageRemovalTask = nil
        NotchController.shared.setActivity(LiveActivity(
            id: .nowPlaying,
            wingWidth: Constants.Geometry.nowPlayingWing,
            priority: 10,
            leading: AnyView(NowPlayingCompactLeading()),
            trailing: AnyView(NowPlayingCompactTrailing())))
        registerPage()
    }

    private func endSession() {
        idleTask?.cancel()
        idleTask = nil
        if contentVisible { setContentVisible(false) }
        guard sessionActive else { return }
        sessionActive = false
        NotchController.shared.removeActivity(.nowPlaying)
        if hiddenBySource {
            hiddenBySource = false
            NotchController.shared.setHidden(false, reason: .sourceAppActive)
        }
        unregisterPageWhenClosed()
    }

    /// The expanded player (362×120, or ≈150 with the volume row). On a
    /// hardware notch the page grows by however much taller the notch is
    /// than the 28 pt simulated one, and the content moves down by the same.
    private func registerPage() {
        let base = isVolumeRowVisible ? NowPlayingMetrics.Expanded.heightWithVolumeRow : NowPlayingMetrics.Expanded.height
        NotchController.shared.registerPage(ExpandedPage(
            id: .nowPlaying,
            height: base + Self.hardwareNotchExtra(),
            priority: 10,
            content: AnyView(NowPlayingExpandedView())))
    }

    /// Extra top inset needed under a hardware notch taller than 28 pt.
    static func hardwareNotchExtra(for geometry: NotchGeometry? = nil) -> CGFloat {
        let resolved = geometry ?? NotchWindowManager.shared.primaryModel?.geometry
        guard let resolved, resolved.hasHardwareNotch else { return 0 }
        return max(0, resolved.closedSize.height - 28)
    }

    /// Never pull the page out from under an open notch: wait until every
    /// notch is closed.
    private func unregisterPageWhenClosed() {
        pageRemovalTask?.cancel()
        pageRemovalTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let anyExpanded = NotchWindowManager.shared.allModels.contains { $0.isExpanded }
                if !anyExpanded { break }
                try? await Task.sleep(for: .seconds(0.5))
            }
            guard let self, !Task.isCancelled, !self.sessionActive else { return }
            NotchController.shared.unregisterPage(.nowPlaying)
            self.isVolumeRowVisible = false
            self.pageRemovalTask = nil
        }
    }

    // MARK: Quick Peek (Part C2 §4)

    private func maybeShowQuickPeek(for current: NowPlayingSnapshot) {
        guard Date() >= peeksAllowedAfter,
              Defaults[.enableQuickPeek], Defaults[.whenSongChanges],
              !current.title.isEmpty,
              lastPeekedIdentity != current.trackIdentity else {
            lastPeekedIdentity = current.trackIdentity
            return
        }
        lastPeekedIdentity = current.trackIdentity
        let controller = NotchController.shared
        guard controller.hideReasons.isEmpty, !controller.isScreenLocked else { return }
        guard !NotchWindowManager.shared.allModels.contains(where: { $0.isExpanded }) else { return }
        controller.showQuickPeek(QuickPeek(
            source: .nowPlaying,
            duration: Defaults[.peekDuration],
            content: AnyView(NowPlayingPeekView())))
    }

    // MARK: Hide while the source app is frontmost

    private func updateSourceHidden() {
        var hide = false
        if Defaults[.hideWhileSourceIsActive], sessionActive, let current = snapshot,
           let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            hide = frontmost == current.sourceAppBundleIdentifier || frontmost == current.bundleIdentifier
        }
        guard hide != hiddenBySource else { return }
        hiddenBySource = hide
        NotchController.shared.setHidden(hide, reason: .sourceAppActive)
    }

    // MARK: Artwork

    private func updateArtwork(for current: NowPlayingSnapshot?) {
        guard let data = current?.artworkData, !data.isEmpty else {
            // Artwork often arrives a beat after the title; keep the old one
            // for the same track, otherwise show the placeholder.
            if let current, current.trackIdentity == artworkTrackIdentity, artworkImage != nil { return }
            guard artworkFingerprint != nil || artworkImage != nil else {
                artworkTrackIdentity = current?.trackIdentity
                return
            }
            artworkFingerprint = nil
            artworkTrackIdentity = current?.trackIdentity
            artworkGeneration += 1
            artworkImage = nil
            palette = .empty
            artworkIdentity += 1
            return
        }

        let fingerprint = Self.fingerprint(data)
        artworkTrackIdentity = current?.trackIdentity
        guard fingerprint != artworkFingerprint else { return }
        artworkFingerprint = fingerprint
        artworkGeneration += 1
        let generation = artworkGeneration

        DispatchQueue.global(qos: .userInitiated).async {
            let processed = NowPlayingArtworkProcessor.process(data)
            let image = processed?.image
            let palette = processed?.palette ?? NowPlayingPalette.empty
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    NowPlayingManager.shared.finishArtwork(image: image, palette: palette, generation: generation)
                }
            }
        }
    }

    private func finishArtwork(image: CGImage?, palette newPalette: NowPlayingPalette, generation: Int) {
        guard generation == artworkGeneration else { return }
        if let image {
            artworkImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        } else {
            artworkImage = nil
        }
        palette = newPalette
        artworkIdentity += 1
    }

    /// Cheap identity for artwork bytes: length plus samples from both ends.
    private static func fingerprint(_ data: Data) -> String {
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(data.prefix(2048))
        hasher.combine(data.suffix(2048))
        if data.count > 8192 {
            let middle = data.count / 2
            hasher.combine(data[(data.startIndex + middle)..<(data.startIndex + middle + 1024)])
        }
        return "\(data.count)-\(hasher.finalize())"
    }

    // MARK: Shuffle / repeat / favorite

    /// Music or Spotify when either is the source (they are scriptable).
    var scriptableApp: NowPlayingAppleScriptSource.App? {
        guard let current = snapshot else { return nil }
        switch current.origin {
        case .music: return .music
        case .spotify: return .spotify
        case .mediaRemote:
            let bundle = current.sourceAppBundleIdentifier
            if bundle == NowPlayingBundleID.music || current.bundleIdentifier == NowPlayingBundleID.music { return .music }
            if bundle == NowPlayingBundleID.spotify || current.bundleIdentifier == NowPlayingBundleID.spotify { return .spotify }
            return nil
        }
    }

    var canFavorite: Bool { scriptableApp == .music }

    private func updateModes() {
        let now = Date()
        let current = snapshot
        let extras = (scriptExtras?.trackIdentity == current?.trackIdentity) ? scriptExtras : nil

        var shuffle = current?.shuffleMode ?? .unknown
        var repeatValue = current?.repeatMode ?? .unknown
        var favorite = current?.isFavorite ?? false
        if let extras {
            if extras.shuffleMode != .unknown { shuffle = extras.shuffleMode }
            if extras.repeatMode != .unknown { repeatValue = extras.repeatMode }
            if let value = extras.isFavorite { favorite = value }
        }
        if let pending = pendingShuffle {
            if now < pending.until { shuffle = pending.mode } else { pendingShuffle = nil }
        }
        if let pending = pendingRepeat {
            if now < pending.until { repeatValue = pending.mode } else { pendingRepeat = nil }
        }
        if let pending = pendingFavorite {
            if now < pending.until { favorite = pending.value } else { pendingFavorite = nil }
        }
        if shuffle != shuffleMode { shuffleMode = shuffle }
        if repeatValue != repeatMode { repeatMode = repeatValue }
        if favorite != isFavorite { isFavorite = favorite }
    }

    /// Reads favorite/shuffle/repeat from Music/Spotify while MediaRemote is
    /// the source.
    private func refreshExtras(after delay: Double = 0) {
        extrasTask?.cancel()
        guard let app = scriptableApp, snapshot?.origin == .mediaRemote else { return }
        extrasTask = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, !Task.isCancelled else { return }
            self.scriptSource.readExtras(for: app) { [weak self] extras in
                guard let self else { return }
                self.scriptExtras = extras
                self.updateModes()
            }
        }
    }

    // MARK: Commands

    func handle(_ command: MediaCommand) {
        switch command {
        case .togglePlayPause: togglePlayPause()
        case .next: next()
        case .previous: previous()
        }
    }

    func togglePlayPause() {
        guard var current = snapshot else { return }
        send(.togglePlayPause)
        // Optimistic: freeze/resume the clock right away; the source confirms.
        let now = Date()
        current.elapsed = current.elapsed(at: now)
        current.timestamp = now
        current.isPlaying.toggle()
        if current.isPlaying && current.playbackRate <= 0 { current.playbackRate = 1 }
        snapshot = current
        isPlaying = current.isPlaying
        applyLifecycle(trackChanged: false)
        NowPlayingSpectrumCenter.shared.reevaluate()
    }

    func next() { send(.next) }

    func previous() { send(.previous) }

    func seek(to position: Double) {
        guard var current = snapshot else { return }
        let clamped = current.duration > 0 ? min(max(0, position), current.duration) : max(0, position)
        send(.seek(clamped))
        current.elapsed = clamped
        current.timestamp = Date()
        snapshot = current
    }

    func elapsed(at date: Date) -> Double {
        snapshot?.elapsed(at: date) ?? 0
    }

    var duration: Double { snapshot?.duration ?? 0 }

    private func send(_ command: NowPlayingRemoteCommand) {
        guard let current = snapshot else { return }
        switch current.origin {
        case .music: scriptSource.perform(command, app: .music)
        case .spotify: scriptSource.perform(command, app: .spotify)
        case .mediaRemote:
            if let backend {
                backend.perform(command)
            } else if let app = scriptableApp {
                scriptSource.perform(command, app: app)
            }
        }
    }

    // MARK: Extra button (Part C2 §3.3)

    func performExtraAction() {
        switch Defaults[.controlChoice] {
        case .favorite: toggleFavorite()
        case .shuffle: toggleShuffle()
        case .repeat: cycleRepeat()
        case .copy: copyLink()
        }
    }

    func toggleShuffle() {
        guard snapshot != nil else { return }
        let target: NowPlayingShuffleMode = shuffleMode.isOn ? .off : .songs
        pendingShuffle = (target, Date().addingTimeInterval(2))
        if let app = scriptableApp {
            scriptSource.perform(.setShuffle(target), app: app)
        } else {
            backend?.perform(.setShuffle(target))
        }
        updateModes()
        refreshExtras(after: 0.6)
    }

    /// off → all → one → off.
    func cycleRepeat() {
        guard snapshot != nil else { return }
        let target = repeatMode.next
        pendingRepeat = (target, Date().addingTimeInterval(2))
        if let app = scriptableApp {
            // Spotify only knows on/off.
            let effective: NowPlayingRepeatMode = app == .spotify ? (repeatMode.isOn ? .off : .all) : target
            pendingRepeat = (effective, Date().addingTimeInterval(2))
            scriptSource.perform(.setRepeat(effective), app: app)
        } else {
            backend?.perform(.setRepeat(target))
        }
        updateModes()
        refreshExtras(after: 0.6)
    }

    func toggleFavorite() {
        guard canFavorite else { return }
        let target = !isFavorite
        pendingFavorite = (target, Date().addingTimeInterval(3))
        updateModes()
        scriptSource.setFavorite(target) { [weak self] success in
            guard let self else { return }
            if !success { self.pendingFavorite = nil }
            self.refreshExtras(after: 0.3)
            self.updateModes()
        }
    }

    /// Copies a share link of the current song: Spotify's open.spotify.com
    /// URL, otherwise the Apple Music catalog URL (no-op for local files).
    func copyLink() {
        guard let current = snapshot, !current.title.isEmpty else { return }
        switch scriptableApp {
        case .spotify:
            if let uri = current.shareURI, let url = Self.spotifyWebURL(from: uri) {
                copyToPasteboard(url)
            } else {
                scriptSource.spotifyURI { [weak self] uri in
                    guard let self, let uri, let url = Self.spotifyWebURL(from: uri) else { return }
                    self.copyToPasteboard(url)
                }
            }
        case .music:
            scriptSource.musicCloudStatus { [weak self] status in
                let local: Set<String> = ["uploaded", "ineligible", "not uploaded", "removed", "error", "duplicate", "no longer available"]
                if let status, local.contains(status.lowercased()) { return }
                self?.lookUpCatalogLink(title: current.title, artist: current.artist)
            }
        case nil:
            lookUpCatalogLink(title: current.title, artist: current.artist)
        }
    }

    private static func spotifyWebURL(from uri: String) -> URL? {
        if uri.hasPrefix("http"), let url = URL(string: uri) { return url }
        let parts = uri.split(separator: ":")
        guard parts.count >= 3, parts[0] == "spotify" else { return nil }
        return URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])")
    }

    private func lookUpCatalogLink(title: String, artist: String) {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(title) \(artist)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let url = components?.url else { return }
        Task { @MainActor [weak self] in
            guard let response = try? await URLSession.shared.data(from: url),
                  let object = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any],
                  let results = object["results"] as? [[String: Any]] else { return }
            let normalizedTitle = title.lowercased()
            let match = results.first { ($0["trackName"] as? String)?.lowercased() == normalizedTitle } ?? results.first
            guard let link = match?["trackViewUrl"] as? String, let linkURL = URL(string: link) else { return }
            self?.copyToPasteboard(linkURL)
        }
    }

    private func copyToPasteboard(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        Haptics.perform(.generic)
        copyFeedbackTask?.cancel()
        withAnimation(Constants.Animations.standard) { didCopyLink = true }
        copyFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(Constants.Animations.standard) { self?.didCopyLink = false }
        }
    }

    // MARK: Volume row

    func toggleVolumeRow() {
        withAnimation(Constants.Animations.contentSwap) {
            isVolumeRowVisible.toggle()
            if sessionActive { registerPage() }
        }
    }

    // MARK: Lock screen

    /// Call when the lock-screen media widget becomes visible.
    func lockScreenWidgetDidShow() {
        guard !lockWidgetVisible else { return }
        lockWidgetVisible = true
        backend?.setLockScreenWidgetVisible(true)
    }

    /// Call when the lock-screen media widget is removed.
    func lockScreenWidgetDidHide() {
        guard lockWidgetVisible else { return }
        lockWidgetVisible = false
        backend?.setLockScreenWidgetVisible(false)
    }
}
