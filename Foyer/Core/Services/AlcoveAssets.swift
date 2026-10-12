import Foundation

/// Optional use of assets from a locally installed copy of Alcove.
///
/// Foyer's repo and releases never contain Alcove's files. Local builds may
/// bundle them from the git-ignored `LocalAssets/Alcove`, and an installed
/// Alcove.app is read at runtime; otherwise Foyer's own assets are used.
enum AlcoveAssets {
    private static let bundleID = "com.henrikruscon.Alcove"

    static let bundle: Bundle? = {
        let candidates = [
            "/Applications/Alcove.app",
            NSHomeDirectory() + "/Applications/Alcove.app",
        ]
        for path in candidates {
            if let b = Bundle(path: path), b.bundleIdentifier == bundleID { return b }
        }
        if let url = NSWorkspaceBundleLookup.url(for: bundleID), let b = Bundle(url: url) { return b }
        return nil
    }()

    static var isAvailable: Bool {
        bundle != nil || Bundle.main.url(forResource: "AlcoveAssets", withExtension: nil) != nil
    }

    /// Assets bundled into a local build from the git-ignored `LocalAssets/Alcove`.
    private static func bundled(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "AlcoveAssets")
    }

    /// e.g. `sound(named: "unlock")` → Alcove's `unlock.caf`.
    static func sound(named name: String) -> URL? {
        if let url = bundled(name, "caf") ?? bundled(name, "m4a") { return url }
        guard let bundle else { return nil }
        return bundle.url(forResource: name, withExtension: "caf")
            ?? bundle.url(forResource: name, withExtension: "m4a")
    }

    /// e.g. `video(named: "airpods-pro-2")` → Alcove's `airpods-pro-2.mp4`.
    static func video(named name: String) -> URL? {
        bundled(name, "mp4") ?? bundle?.url(forResource: name, withExtension: "mp4")
    }
}

import AppKit

private enum NSWorkspaceBundleLookup {
    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}
