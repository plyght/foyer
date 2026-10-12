import AVFoundation
import AppKit
import CoreFoundation
import Darwin
import Foundation
import MediaPlayer

private func log(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

private func explicitKey(from symbol: String, handle: UnsafeMutableRawPointer?) -> String? {
    guard let handle, let address = dlsym(handle, symbol) else { return nil }
    let value = address.assumingMemoryBound(to: Optional<CFString>.self).pointee
    return value as String?
}

private func attemptNumber() -> Int {
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: "--attempt"), arguments.indices.contains(index + 1) {
        return Int(arguments[index + 1]) ?? 0
    }
    for attempt in 1...3 where arguments.contains("--attempt\(attempt)") {
        return attempt
    }
    return 0
}

private func quitAfterDelay() -> TimeInterval? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: "--quit-after"), arguments.indices.contains(index + 1) else {
        return nil
    }
    return TimeInterval(arguments[index + 1])
}

private final class ProbeAppDelegate: NSObject, NSApplicationDelegate, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var metadataTimer: Timer?
    private var mediaRemoteHandle: UnsafeMutableRawPointer?
    private var baseInfo: [String: Any] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let attempt = attemptNumber()
        mediaRemoteHandle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY
        )
        log("NowPlayingProbe started; attempt=\(attempt)")
        if mediaRemoteHandle == nil {
            log("MediaRemote.framework dlopen failed: \(String(cString: dlerror()))")
        } else {
            log("MediaRemote.framework: loaded")
        }

        let audioPath = "/Users/devin/alcove-research/live_v3/perf/perf_noise_100s.m4a"
        do {
            player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: audioPath))
            player?.numberOfLoops = -1
            player?.volume = 1
            player?.delegate = self
            player?.prepareToPlay()
            let started = player?.play() ?? false
            log("AVAudioPlayer: path=\(audioPath) duration=\(player?.duration ?? 0) play=\(started) isPlaying=\(player?.isPlaying ?? false)")
        } catch {
            log("AVAudioPlayer error: \(error)")
        }

        registerRemoteCommands()
        publishBaseInfo()

        switch attempt {
        case 1:
            applyAttemptOne()
        case 2:
            applyAttemptTwo()
        case 3:
            applyAttemptThree()
        default:
            log("No explicit-track attempt selected")
        }

        metadataTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshPlaybackMetadata()
        }
        if let delay = quitAfterDelay() {
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                log("Quit timer fired")
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        metadataTimer?.invalidate()
        player?.stop()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        if let mediaRemoteHandle {
            dlclose(mediaRemoteHandle)
        }
        log("NowPlayingProbe stopped")
    }

    private func publishBaseInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "Probe Explicit Track",
            MPMediaItemPropertyArtist: "devin",
            MPMediaItemPropertyAlbumTitle: "NowPlayingProbe",
            MPMediaItemPropertyPlaybackDuration: player?.duration ?? 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.currentTime ?? 0,
            MPNowPlayingInfoPropertyPlaybackRate: player?.isPlaying == true ? 1 : 0
        ]
        if let url = Bundle.main.url(forResource: "artwork", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            log("Artwork loaded: \(url.path)")
        } else {
            log("Artwork unavailable")
        }
        baseInfo = info
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = .playing
        log("MPNowPlayingInfoCenter published title='Probe Explicit Track' artist='devin' playbackState=playing")
    }

    private func refreshPlaybackMetadata() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentTime ?? 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = player?.isPlaying == true ? 1 : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            let result = self.player?.play() ?? false
            self.refreshPlaybackMetadata()
            log("Remote command: play result=\(result)")
            return result ? .success : .commandFailed
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.player?.pause()
            self.refreshPlaybackMetadata()
            log("Remote command: pause")
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.player?.currentTime = 0
            self.refreshPlaybackMetadata()
            log("Remote command: next")
            return .success
        }
        log("MPRemoteCommandCenter play/pause/next handlers registered")
    }

    private func applyAttemptOne() {
        guard let key = explicitKey(
            from: "kMRMediaRemoteNowPlayingInfoIsExplicitTrack",
            handle: mediaRemoteHandle
        ) else {
            log("Attempt 1: dlsym kMRMediaRemoteNowPlayingInfoIsExplicitTrack failed")
            return
        }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? baseInfo
        info[key] = true
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        log("Attempt 1: resolved kMRMediaRemoteNowPlayingInfoIsExplicitTrack value='\(key)'; added true to MPNowPlayingInfoCenter dictionary")
    }

    private func applyAttemptTwo() {
        let frameworkPath = "/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer"
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dyld_info")
        process.arguments = ["-exports", frameworkPath]
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let exportText = String(decoding: data, as: UTF8.self)
            let matchingSymbols = exportText
                .components(separatedBy: .newlines)
                .compactMap { line -> String? in
                    guard let symbol = line.split(whereSeparator: \.isWhitespace).last.map(String.init) else {
                        return nil
                    }
                    let normalized = symbol.hasPrefix("_") ? String(symbol.dropFirst()) : symbol
                    guard normalized.localizedCaseInsensitiveContains("MPNowPlayingInfoProperty"),
                          normalized.localizedCaseInsensitiveContains("xplicit") else {
                        return nil
                    }
                    return normalized
                }

            guard !matchingSymbols.isEmpty else {
                let errorText = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if process.terminationStatus == 0 {
                    log("Attempt 2: no exported MPNowPlayingInfoProperty*xplicit* constant found in MediaPlayer.framework")
                } else {
                    log("Attempt 2: dyld_info failed status=\(process.terminationStatus): \(errorText)")
                }
                return
            }

            let mediaPlayerHandle = dlopen(frameworkPath, RTLD_LAZY)
            guard let key = matchingSymbols.lazy.compactMap({ explicitKey(from: $0, handle: mediaPlayerHandle) }).first else {
                log("Attempt 2: matching exported symbols found but none resolved to a CFString constant: \(matchingSymbols.joined(separator: ", "))")
                return
            }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? baseInfo
            info[key] = true
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            log("Attempt 2: found exported constant(s) \(matchingSymbols.joined(separator: ", ")); resolved key='\(key)' and added true")
        } catch {
            log("Attempt 2: could not run dyld_info: \(error)")
        }
    }

    private func applyAttemptThree() {
        guard let mediaRemoteHandle,
              let address = dlsym(mediaRemoteHandle, "MRMediaRemoteSetNowPlayingInfo") else {
            log("Attempt 3: dlsym MRMediaRemoteSetNowPlayingInfo failed")
            return
        }
        guard let key = explicitKey(
            from: "kMRMediaRemoteNowPlayingInfoIsExplicitTrack",
            handle: mediaRemoteHandle
        ) else {
            log("Attempt 3: could not resolve kMRMediaRemoteNowPlayingInfoIsExplicitTrack")
            return
        }
        typealias SetNowPlayingInfo = @convention(c) (CFDictionary) -> Void
        let setInfo = unsafeBitCast(address, to: SetNowPlayingInfo.self)
        let info: [String: Any] = [
            key: true,
            MPMediaItemPropertyTitle: "Probe Explicit Track",
            MPMediaItemPropertyArtist: "devin"
        ]
        setInfo(info as NSDictionary as CFDictionary)
        log("Attempt 3: called MRMediaRemoteSetNowPlayingInfo(CFDictionary) with explicit key='\(key)', title, and artist")
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
private let delegate = ProbeAppDelegate()
application.delegate = delegate
application.run()
