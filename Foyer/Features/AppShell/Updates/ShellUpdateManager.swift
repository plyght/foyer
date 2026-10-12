import AppKit
import Defaults
import SwiftUI

/// A GitHub release as returned by `api.github.com/repos/<repo>/releases`.
struct ShellGitHubRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: URL
        let size: Int?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let draft: Bool?
    let prerelease: Bool?
    let htmlURL: URL?
    let publishedAt: Date?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, draft, prerelease
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }

    /// Tag without the leading "v" ("v1.2.0" → "1.2.0").
    var version: String {
        var tag = tagName.trimmingCharacters(in: .whitespaces)
        if tag.hasPrefix("v") || tag.hasPrefix("V") { tag.removeFirst() }
        return tag
    }

    /// The archive CI publishes on every `v*` tag (`Foyer.zip`), falling back
    /// to the first zip asset.
    var zipAsset: Asset? {
        assets.first(where: { $0.name == "Foyer.zip" })
            ?? assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })
    }
}

enum ShellUpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(String)
    case downloading(Double)
    case installing
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }
}

enum ShellUpdateError: LocalizedError {
    case http(Int)
    case rateLimited
    case noAsset
    case downloadIncomplete
    case extractionFailed(Int32)
    case noAppInArchive
    case wrongBundle(String?)
    case notWritable(String)

    var errorDescription: String? {
        switch self {
        case .http(let code): return "The update server answered with HTTP \(code)."
        case .rateLimited: return "GitHub's rate limit was reached. Try again later."
        case .noAsset: return "The release does not contain Foyer.zip."
        case .downloadIncomplete: return "The download did not complete."
        case .extractionFailed(let status): return "The update archive could not be extracted (ditto exited with \(status))."
        case .noAppInArchive: return "No .app found in update archive."
        case .wrongBundle(let id): return "The update contains an unexpected app (\(id ?? "unknown"))."
        case .notWritable(let path): return "Foyer cannot replace \(path). Move Foyer to Applications and try again."
        }
    }
}

/// Self-updater backed by GitHub Releases of `Constants.updateRepository`.
/// Mirrors Alcove's flow (Part G §11): periodic check, download the zip asset
/// to a cache folder, a second version check, then install through the
/// helper XPC (`installUpdate(withZipPath:appBundlePath:reply:)`), falling
/// back to an in-process `ditto` install and relaunch.
@MainActor
final class ShellUpdateManager: ObservableObject {
    static let shared = ShellUpdateManager()

    @Published private(set) var state: ShellUpdateState = .idle
    @Published private(set) var latestRelease: ShellGitHubRelease?
    @Published private(set) var lastChecked: Date?

    /// Alcove's timer is six hours; Foyer checks daily (plus at launch).
    private let checkInterval: Duration = .seconds(24 * 60 * 60)
    private var periodicTask: Task<Void, Never>?
    private var observation: Defaults.Observation?
    private var lastAnnouncedVersion: String?
    private var lastProgressReport: Double = -1

    private init() {}

    var currentVersion: String { ShellAppInfo.version }

    func start() {
        schedulePeriodicChecks()
        observation = Defaults.observe(.automaticallyCheckForUpdates, options: []) { change in
            let enabled = change.newValue
            Task { @MainActor in
                if enabled {
                    ShellUpdateManager.shared.schedulePeriodicChecks()
                } else {
                    ShellUpdateManager.shared.periodicTask?.cancel()
                    ShellUpdateManager.shared.periodicTask = nil
                }
            }
        }
    }

    private func schedulePeriodicChecks() {
        periodicTask?.cancel()
        guard Defaults[.automaticallyCheckForUpdates] else { return }
        periodicTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                if Defaults[.automaticallyCheckForUpdates] {
                    await ShellUpdateManager.shared.checkForUpdates(userInitiated: false)
                }
                try? await Task.sleep(for: ShellUpdateManager.shared.checkInterval)
            }
        }
    }

    // MARK: Checking

    func checkForUpdates(userInitiated: Bool) async {
        guard !state.isBusy else { return }
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            lastChecked = Date()
            if let release, release.zipAsset != nil, ShellVersion.isVersion(release.version, newerThan: currentVersion) {
                latestRelease = release
                state = .available(release.version)
                if !userInitiated { announce(release) }
            } else {
                latestRelease = nil
                state = .upToDate
            }
        } catch {
            ShellLog.logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    private func fetchLatestRelease() async throws -> ShellGitHubRelease? {
        let base = "https://api.github.com/repos/\(Constants.updateRepository)/releases"
        let wantsPrereleases = Defaults[.earlyBirdUpdates]
        guard let url = URL(string: wantsPrereleases ? base + "?per_page=10" : base + "/latest") else { return nil }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Foyer/\(currentVersion) (macOS \(ProcessInfo.processInfo.operatingSystemVersionString))", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { return nil } // no published release yet
            if http.statusCode == 403 || http.statusCode == 429 { throw ShellUpdateError.rateLimited }
            guard (200..<300).contains(http.statusCode) else { throw ShellUpdateError.http(http.statusCode) }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if wantsPrereleases {
            let releases = try decoder.decode([ShellGitHubRelease].self, from: data)
            let candidates = releases.filter { $0.draft != true && $0.zipAsset != nil }
            return candidates.max { ShellVersion.isVersion($1.version, newerThan: $0.version) }
        }
        return try decoder.decode(ShellGitHubRelease.self, from: data)
    }

    /// Briefly shows the new version in the notch after an automatic check.
    private func announce(_ release: ShellGitHubRelease) {
        guard lastAnnouncedVersion != release.version else { return }
        lastAnnouncedVersion = release.version
        let accent = Constants.SettingsWindow.accent
        NotchController.shared.post(NotchNotification(
            kind: .update,
            category: .other,
            wingWidth: 52,
            duration: 5,
            leading: AnyView(
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
            ),
            trailing: AnyView(
                Text(release.version)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(accent)
            )
        ))
    }

    // MARK: Download and install

    func downloadAndInstall() async {
        if latestRelease == nil || state == .upToDate || state == .idle {
            await checkForUpdates(userInitiated: true)
        }
        guard let release = latestRelease, case .available = state else { return }
        guard let asset = release.zipAsset else {
            state = .failed(ShellUpdateError.noAsset.localizedDescription)
            return
        }

        do {
            state = .downloading(0)
            lastProgressReport = -1
            let zipURL = try await download(asset: asset, version: release.version)

            // Second check before installing (Alcove re-validates the release).
            guard ShellVersion.isVersion(release.version, newerThan: currentVersion) else {
                state = .upToDate
                return
            }

            state = .installing
            let appURL = Bundle.main.bundleURL
            if await installViaHelper(zipPath: zipURL.path, appPath: appURL.path) {
                // The helper waits for this process to exit, then opens the
                // new bundle itself.
                NSApp.terminate(nil)
                return
            }
            ShellLog.logger.notice("Helper install unavailable; installing in-process")
            let bundleID = Bundle.main.bundleIdentifier
            try await Task.detached(priority: .userInitiated) {
                try ShellUpdateManager.installInProcess(zipURL: zipURL, appURL: appURL, expectedBundleID: bundleID)
            }.value
            relaunchAndTerminate()
        } catch {
            ShellLog.logger.error("Update failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    private func reportProgress(_ fraction: Double) {
        guard case .downloading = state else { return }
        // Throttle UI updates to whole percents.
        let rounded = (fraction * 100).rounded() / 100
        guard rounded != lastProgressReport else { return }
        lastProgressReport = rounded
        state = .downloading(rounded)
    }

    private func download(asset: ShellGitHubRelease.Asset, version: String) async throws -> URL {
        let fileManager = FileManager.default
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let folder = caches.appendingPathComponent("Foyer/Updates", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("Foyer-\(version).zip")

        var request = URLRequest(url: asset.browserDownloadURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Foyer/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let delegate = ShellDownloadDelegate(destination: destination) { fraction in
            Task { @MainActor in
                ShellUpdateManager.shared.reportProgress(fraction)
            }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            delegate.setContinuation(continuation)
            session.downloadTask(with: request).resume()
        }
    }

    /// Asks FoyerHelper.xpc to unzip over the bundle and relaunch. Returns
    /// false when the helper is missing, errors or does not answer in time.
    private func installViaHelper(zipPath: String, appPath: String) async -> Bool {
        let connection = NSXPCConnection(serviceName: FoyerHelperConstants.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: FoyerHelperProtocol.self)
        connection.resume()

        let succeeded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = ShellOnce()
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                ShellLog.logger.error("Helper connection failed: \(error.localizedDescription, privacy: .public)")
                if once.claim() { continuation.resume(returning: false) }
            }
            guard let helper = proxy as? FoyerHelperProtocol else {
                if once.claim() { continuation.resume(returning: false) }
                return
            }
            helper.installUpdate(withZipPath: zipPath, appBundlePath: appPath) { success, message in
                if let message, !success {
                    ShellLog.logger.error("Helper install failed: \(message, privacy: .public)")
                }
                if once.claim() { continuation.resume(returning: success) }
            }
            // Extraction of a large archive can take a while; give up after 3 minutes.
            DispatchQueue.global().asyncAfter(deadline: .now() + 180) {
                if once.claim() { continuation.resume(returning: false) }
            }
        }
        if !succeeded { connection.invalidate() }
        return succeeded
    }

    /// Fallback installer: `ditto -xk` into a replacement directory on the
    /// same volume, verify the bundle id, then atomically replace the bundle.
    nonisolated static func installInProcess(zipURL: URL, appURL: URL, expectedBundleID: String?) throws {
        let fileManager = FileManager.default
        let parent = appURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parent.path) else {
            throw ShellUpdateError.notWritable(appURL.path)
        }
        let work = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appURL, create: true)
        defer { try? fileManager.removeItem(at: work) }

        let status = try runProcess("/usr/bin/ditto", ["-xk", zipURL.path, work.path])
        guard status == 0 else { throw ShellUpdateError.extractionFailed(status) }

        let contents = try fileManager.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
        guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
            throw ShellUpdateError.noAppInArchive
        }
        let newBundleID = Bundle(url: newApp)?.bundleIdentifier
        if let expectedBundleID, newBundleID != expectedBundleID {
            throw ShellUpdateError.wrongBundle(newBundleID)
        }
        _ = try? runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
        _ = try fileManager.replaceItemAt(appURL, withItemAt: newApp, backupItemName: nil, options: [])
        try? fileManager.removeItem(at: zipURL)
    }

    @discardableResult
    nonisolated static func runProcess(_ path: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Relaunches the (new) bundle once this process has exited.
    private func relaunchAndTerminate() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        do {
            try process.run()
        } catch {
            ShellLog.logger.error("Could not schedule relaunch: \(error.localizedDescription, privacy: .public)")
        }
        NSApp.terminate(nil)
    }
}

/// Download delegate that moves the finished file into place and resumes a
/// continuation exactly once.
private final class ShellDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?

    init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func setContinuation(_ continuation: CheckedContinuation<URL, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(ShellUpdateError.http(http.statusCode)))
            return
        }
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // No-op when didFinishDownloadingTo already resumed.
        finish(.failure(error ?? (ShellUpdateError.downloadIncomplete as Error)))
    }
}

/// Semantic-version comparison: "1.10.0" > "1.9.2", "1.2.0" > "1.2.0-beta.3".
enum ShellVersion {
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = split(lhs)
        let right = split(rhs)
        let count = max(left.numbers.count, right.numbers.count)
        for index in 0..<count {
            let l = index < left.numbers.count ? left.numbers[index] : 0
            let r = index < right.numbers.count ? right.numbers[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        switch (left.prerelease, right.prerelease) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case (let l?, let r?): return l.compare(r, options: .numeric)
        }
    }

    private static func split(_ version: String) -> (numbers: [Int], prerelease: String?) {
        var text = version.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        // Drop build metadata ("+abc").
        if let plus = text.firstIndex(of: "+") { text = String(text[..<plus]) }
        var prerelease: String?
        if let dash = text.firstIndex(of: "-") {
            prerelease = String(text[text.index(after: dash)...])
            text = String(text[..<dash])
        }
        let numbers = text.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        return (numbers, prerelease)
    }
}
