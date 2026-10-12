import AppKit
import Defaults
import Luminare
import SwiftUI

/// About: version, Check for Updates…, automatic updates and links. Foyer
/// has no licence, trial or feedback form.
struct SettingsAboutPane: View {
    @Default(.automaticallyCheckForUpdates) private var automaticallyCheckForUpdates
    @ObservedObject private var updates = ShellUpdateManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LuminareSection {
                header
                checkButton
                if let version = availableVersion {
                    availableRow(version: version)
                }
                if let progress = downloadProgress {
                    progressRow(progress)
                }
                SettingsToggleRow(
                    "Automatically check for updates", isOn: $automaticallyCheckForUpdates,
                    symbol: "arrow.triangle.2.circlepath", symbolColor: SettingsMetrics.accent
                )
            }

            LuminareSection("Links") {
                linkRow("GitHub repository", symbol: "chevron.left.forwardslash.chevron.right", url: ShellAppInfo.repositoryURL)
                linkRow("Release notes", symbol: "doc.text", url: ShellAppInfo.releasesURL)
                linkRow("Report an issue", symbol: "exclamationmark.bubble", url: ShellAppInfo.issuesURL)
            }

            Text("Foyer is free and open-source software.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Rows

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("Foyer")
                    .font(.system(size: 17, weight: .semibold))
                Text("Version \(ShellAppInfo.version) (\(ShellAppInfo.build))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(statusColor)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
    }

    private var checkButton: some View {
        Button {
            Task { @MainActor in
                await ShellUpdateManager.shared.checkForUpdates(userInitiated: true)
            }
        } label: {
            HStack(spacing: 6) {
                if updates.state == .checking {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                }
                Text("Check for Updates…")
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SettingsNestedRowButtonStyle())
        .disabled(updates.state.isBusy)
    }

    private func availableRow(version: String) -> some View {
        LuminareCompose {
            Button("Install & Relaunch") {
                Task { @MainActor in
                    await ShellUpdateManager.shared.downloadAndInstall()
                }
            }
            .buttonStyle(SettingsCapsuleButtonStyle(prominent: true))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(SettingsMetrics.accent)
                Text("Foyer \(version) is available")
                if let notes = updates.latestRelease?.htmlURL {
                    Button {
                        NSWorkspace.shared.open(notes)
                    } label: {
                        Text("Notes")
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsMetrics.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func progressRow(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Downloading… \(Int((progress * 100).rounded())) %")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(SettingsMetrics.accent)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func linkRow(_ title: String, symbol: String, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsMetrics.accent)
                    .frame(width: 18)
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(SettingsNestedRowButtonStyle())
    }

    // MARK: State

    private var availableVersion: String? {
        if case .available(let version) = updates.state { return version }
        return nil
    }

    private var downloadProgress: Double? {
        if case .downloading(let progress) = updates.state { return progress }
        return nil
    }

    private var statusText: String {
        switch updates.state {
        case .idle:
            if let date = updates.lastChecked {
                return "Last checked \(date.formatted(date: .abbreviated, time: .shortened))"
            }
            return "Updates come from GitHub Releases."
        case .checking: return "Checking for updates…"
        case .upToDate: return "Foyer is up to date."
        case .available(let version): return "Version \(version) is available."
        case .downloading: return "Downloading update…"
        case .installing: return "Installing update…"
        case .failed(let message): return message
        }
    }

    private var statusColor: Color {
        switch updates.state {
        case .failed: return Color.red
        case .available: return SettingsMetrics.accent
        default: return Color.secondary
        }
    }
}
