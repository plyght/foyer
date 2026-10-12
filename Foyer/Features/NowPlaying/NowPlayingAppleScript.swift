import AppKit
import Foundation

/// Music and Spotify over AppleScript (Part A §6 "ScriptingBridge for
/// Music/Spotify", Part C2 §3.3). Used as the source when MediaRemote is
/// unavailable or when Settings pins a specific music app, and for the extra
/// button (favorite / shuffle / repeat / copy link) state of those two apps.
///
/// Scripts run on one serial background queue (NSAppleScript blocks), and an
/// app is only ever addressed while it is running so Foyer never launches it.
@MainActor
final class NowPlayingAppleScriptSource {
    enum App: Equatable {
        case music, spotify

        var bundleIdentifier: String {
            switch self {
            case .music: return NowPlayingBundleID.music
            case .spotify: return NowPlayingBundleID.spotify
            }
        }

        var origin: NowPlayingOrigin {
            switch self {
            case .music: return .music
            case .spotify: return .spotify
            }
        }

        var isRunning: Bool {
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        }

        var processIdentifier: pid_t? {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.processIdentifier
        }

        /// Distributed notification each app posts on player changes.
        var changeNotification: String {
            switch self {
            case .music: return "com.apple.Music.playerInfo"
            case .spotify: return "com.spotify.client.PlaybackStateChanged"
            }
        }
    }

    /// Apps to follow, in priority order (a playing app wins over a paused one).
    var apps: [App] = [] {
        didSet { if apps != oldValue { restart() } }
    }

    private(set) var snapshot: NowPlayingSnapshot?
    var onUpdate: (@MainActor (NowPlayingSnapshot?) -> Void)?

    private let runner = NowPlayingScriptRunner()
    private var pollTask: Task<Void, Never>?
    private var tokens: [NSObjectProtocol] = []
    private var artworkCache: [String: Data] = [:]
    private var artworkRequests: Set<String> = []
    private var unauthorized: Set<String> = []
    private var isRunning = false

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = DistributedNotificationCenter.default()
        for app in [App.music, App.spotify] {
            let token = center.addObserver(forName: Notification.Name(app.changeNotification), object: nil,
                                           queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            tokens.append(token)
        }
        schedulePolling()
        poll()
    }

    func stop() {
        isRunning = false
        pollTask?.cancel()
        pollTask = nil
        let center = DistributedNotificationCenter.default()
        tokens.forEach { center.removeObserver($0) }
        tokens.removeAll()
        if snapshot != nil {
            snapshot = nil
            onUpdate?(nil)
        }
    }

    private func restart() {
        guard isRunning else { return }
        unauthorized.removeAll()
        poll()
    }

    /// Clears the "not authorized" memory (after the user grants Automation).
    func resetAuthorization() {
        unauthorized.removeAll()
        poll()
    }

    private func schedulePolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let playing = self?.snapshot?.isPlaying ?? false
                let interval = playing ? NowPlayingMetrics.scriptPollPlaying : NowPlayingMetrics.scriptPollPaused
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                self?.poll()
            }
        }
    }

    // MARK: Polling

    func poll() {
        guard isRunning else { return }
        let candidates = apps.filter { $0.isRunning && !unauthorized.contains($0.bundleIdentifier) }
        guard !candidates.isEmpty else {
            publish(nil)
            return
        }
        let round = NowPlayingScriptPollRound(remaining: candidates.count)
        for app in candidates {
            let source = Self.stateScript(for: app)
            runner.run(source) { [weak self] descriptor, errorNumber in
                guard let self else { return }
                if errorNumber == -1743 { self.unauthorized.insert(app.bundleIdentifier) }
                if let descriptor, var snapshot = Self.parseState(descriptor, app: app) {
                    snapshot.processIdentifier = app.processIdentifier
                    round.results[app] = snapshot
                }
                round.remaining -= 1
                if round.remaining == 0 { self.finishPoll(order: candidates, results: round.results) }
            }
        }
    }

    private func finishPoll(order: [App], results: [App: NowPlayingSnapshot]) {
        let ordered = order.compactMap { results[$0] }
        let chosen = ordered.first(where: { $0.isPlaying }) ?? ordered.first
        guard var chosen else { publish(nil); return }

        // Keep artwork across polls; fetch it once per track.
        let key = chosen.trackIdentity
        if let cached = artworkCache[key] {
            chosen.artworkData = cached
        } else if let app = order.first(where: { $0.origin == chosen.origin }) {
            fetchArtwork(for: app, key: key, artworkURL: chosen.artworkURL)
        }
        publish(chosen)
    }

    private func publish(_ new: NowPlayingSnapshot?) {
        // Ignore pure position drift between polls (the extrapolation covers it).
        if let old = snapshot, let new, Self.isSameState(old, new) { return }
        snapshot = new
        onUpdate?(new)
    }

    private static func isSameState(_ a: NowPlayingSnapshot, _ b: NowPlayingSnapshot) -> Bool {
        guard a.trackIdentity == b.trackIdentity, a.isPlaying == b.isPlaying,
              a.shuffleMode == b.shuffleMode, a.repeatMode == b.repeatMode,
              a.isFavorite == b.isFavorite, a.artworkData == b.artworkData,
              abs(a.duration - b.duration) < 0.5 else { return false }
        // Same track: only a seek (position off the extrapolation) counts.
        let predicted = a.elapsed(at: b.timestamp)
        return abs(predicted - b.elapsed) < 1.5
    }

    private func fetchArtwork(for app: App, key: String, artworkURL: URL?) {
        guard !artworkRequests.contains(key) else { return }
        artworkRequests.insert(key)
        switch app {
        case .music:
            let source = """
            if application id "com.apple.Music" is running then
                tell application id "com.apple.Music"
                    try
                        return raw data of artwork 1 of current track
                    end try
                end tell
            end if
            return ""
            """
            runner.run(source) { [weak self] descriptor, _ in
                guard let self else { return }
                self.artworkRequests.remove(key)
                guard let data = descriptor?.data, data.count > 64 else { return }
                self.storeArtwork(data, key: key)
            }
        case .spotify:
            guard let artworkURL else { artworkRequests.remove(key); return }
            Task { @MainActor [weak self] in
                let data = try? await URLSession.shared.data(from: artworkURL).0
                guard let self else { return }
                self.artworkRequests.remove(key)
                guard let data, !data.isEmpty else { return }
                self.storeArtwork(data, key: key)
            }
        }
    }

    private func storeArtwork(_ data: Data, key: String) {
        if artworkCache.count > 8 { artworkCache.removeAll() }
        artworkCache[key] = data
        guard var current = snapshot, current.trackIdentity == key else { return }
        current.artworkData = data
        snapshot = current
        onUpdate?(current)
    }

    // MARK: Commands

    func perform(_ command: NowPlayingRemoteCommand, app: App) {
        guard app.isRunning else { return }
        let target = "application id \"\(app.bundleIdentifier)\""
        let body: String
        switch command {
        case .togglePlayPause: body = "playpause"
        case .next: body = "next track"
        case .previous: body = "previous track"
        case .seek(let position): body = "set player position to \(String(format: "%.2f", max(0, position)))"
        case .setShuffle(let mode):
            switch app {
            case .music: body = "set shuffle enabled to \(mode.isOn ? "true" : "false")"
            case .spotify: body = "set shuffling to \(mode.isOn ? "true" : "false")"
            }
        case .setRepeat(let mode):
            switch app {
            case .music:
                let value: String
                switch mode {
                case .one: value = "one"
                case .all: value = "all"
                default: value = "off"
                }
                body = "set song repeat to \(value)"
            case .spotify: body = "set repeating to \(mode.isOn ? "true" : "false")"
            }
        }
        runner.run("tell \(target) to \(body)") { [weak self] _, _ in
            self?.poll()
        }
    }

    /// Music: `favorited` (macOS 14+) with `loved` as fallback (Part C2 §3.3).
    func setFavorite(_ favorite: Bool, completion: @escaping @MainActor (Bool) -> Void) {
        guard App.music.isRunning else { completion(false); return }
        let flag = favorite ? "true" : "false"
        let source = """
        tell application id "com.apple.Music"
            try
                set favorited of current track to \(flag)
                return true
            on error
                try
                    set loved of current track to \(flag)
                    return true
                end try
            end try
            return false
        end tell
        """
        runner.run(source) { [weak self] descriptor, _ in
            completion(descriptor?.booleanValue ?? false)
            self?.poll()
        }
    }

    /// Reads the extra-button state of Music/Spotify while MediaRemote is the
    /// main source (MediaRemote does not expose "favorited").
    func readExtras(for app: App, completion: @escaping @MainActor (NowPlayingSnapshot?) -> Void) {
        guard app.isRunning, !unauthorized.contains(app.bundleIdentifier) else { completion(nil); return }
        runner.run(Self.stateScript(for: app)) { descriptor, _ in
            completion(descriptor.flatMap { Self.parseState($0, app: app) })
        }
    }

    /// Spotify's `spotify url` of the current track.
    func spotifyURI(completion: @escaping @MainActor (String?) -> Void) {
        guard App.spotify.isRunning else { completion(nil); return }
        runner.run("tell application id \"com.spotify.client\" to return spotify url of current track") { descriptor, _ in
            completion(descriptor?.stringValue)
        }
    }

    /// Music's `cloud status` (catalog items are subscription/purchased/matched).
    func musicCloudStatus(completion: @escaping @MainActor (String?) -> Void) {
        guard App.music.isRunning else { completion(nil); return }
        let source = """
        tell application id "com.apple.Music"
            try
                return (cloud status of current track) as string
            end try
        end tell
        return ""
        """
        runner.run(source) { descriptor, _ in
            completion(descriptor?.stringValue)
        }
    }

    // MARK: Scripts

    private static func stateScript(for app: App) -> String {
        switch app {
        case .music:
            return """
            if application id "com.apple.Music" is running then
                tell application id "com.apple.Music"
                    set st to (player state as string)
                    if st is "stopped" then return {"stopped"}
                    set t to current track
                    set fav to false
                    try
                        set fav to favorited of t
                    on error
                        try
                            set fav to loved of t
                        end try
                    end try
                    set rp to "off"
                    try
                        set rp to (song repeat as string)
                    end try
                    set sh to false
                    try
                        set sh to shuffle enabled
                    end try
                    set pos to 0
                    try
                        set pos to player position
                    end try
                    return {st, (name of t) as string, (artist of t) as string, (album of t) as string, (duration of t), pos, sh, rp, fav, "", ""}
                end tell
            end if
            return {"stopped"}
            """
        case .spotify:
            return """
            if application id "com.spotify.client" is running then
                tell application id "com.spotify.client"
                    set st to (player state as string)
                    if st is "stopped" then return {"stopped"}
                    set t to current track
                    set au to ""
                    try
                        set au to artwork url of t
                    end try
                    set su to ""
                    try
                        set su to spotify url of t
                    end try
                    return {st, (name of t) as string, (artist of t) as string, (album of t) as string, ((duration of t) / 1000), player position, shuffling, repeating, false, au, su}
                end tell
            end if
            return {"stopped"}
            """
        }
    }

    nonisolated private static func parseState(_ descriptor: NSAppleEventDescriptor, app: App) -> NowPlayingSnapshot? {
        guard descriptor.numberOfItems >= 1 else { return nil }
        let state = descriptor.atIndex(1)?.stringValue ?? "stopped"
        guard state != "stopped", descriptor.numberOfItems >= 11 else { return nil }

        func string(_ index: Int) -> String { descriptor.atIndex(index)?.stringValue ?? "" }
        func double(_ index: Int) -> Double {
            guard let item = descriptor.atIndex(index) else { return 0 }
            if let text = item.stringValue, let value = Double(text.replacingOccurrences(of: ",", with: ".")) {
                return value
            }
            return item.doubleValue
        }
        func bool(_ index: Int) -> Bool {
            guard let item = descriptor.atIndex(index) else { return false }
            if let text = item.stringValue?.lowercased() { return text == "true" || text == "yes" }
            return item.booleanValue
        }

        var snapshot = NowPlayingSnapshot()
        snapshot.origin = app.origin
        snapshot.bundleIdentifier = app.bundleIdentifier
        snapshot.isPlaying = state == "playing"
        snapshot.playbackRate = snapshot.isPlaying ? 1 : 0
        snapshot.title = string(2)
        snapshot.artist = string(3)
        snapshot.album = string(4)
        snapshot.duration = max(0, double(5))
        snapshot.elapsed = max(0, double(6))
        snapshot.timestamp = Date()
        snapshot.shuffleMode = bool(7) ? .songs : .off
        switch app {
        case .music:
            switch string(8) {
            case "one": snapshot.repeatMode = .one
            case "all": snapshot.repeatMode = .all
            default: snapshot.repeatMode = .off
            }
            snapshot.isFavorite = bool(9)
            snapshot.displayName = "Music"
        case .spotify:
            snapshot.repeatMode = bool(8) ? .all : .off
            snapshot.isFavorite = nil
            let artwork = string(10)
            snapshot.artworkURL = artwork.isEmpty ? nil : URL(string: artwork)
            let uri = string(11)
            snapshot.shareURI = uri.isEmpty ? nil : uri
            snapshot.displayName = "Spotify"
        }
        return snapshot
    }
}

/// Results of one polling round across Music and Spotify.
final class NowPlayingScriptPollRound {
    var remaining: Int
    var results: [NowPlayingAppleScriptSource.App: NowPlayingSnapshot] = [:]
    init(remaining: Int) { self.remaining = remaining }
}

/// Runs NSAppleScript sources on one serial queue and calls back on the main actor.
final class NowPlayingScriptRunner {
    private let queue = DispatchQueue(label: "app.foyer.nowplaying.applescript", qos: .userInitiated)
    private var cache: [String: NSAppleScript] = [:]

    func run(_ source: String, completion: @escaping @MainActor (NSAppleEventDescriptor?, Int?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let script: NSAppleScript?
            if let cached = self.cache[source] {
                script = cached
            } else {
                script = NSAppleScript(source: source)
                if let script, self.cache.count < 32 { self.cache[source] = script }
            }
            var errorInfo: NSDictionary?
            let output = script?.executeAndReturnError(&errorInfo)
            let errorNumber = (errorInfo?[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            let result: NSAppleEventDescriptor? = errorInfo == nil ? output : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion(result, errorNumber)
                }
            }
        }
    }
}
