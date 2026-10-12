import AVFoundation
import AppKit

/// The 13 sound events Foyer can play (same set as Alcove's bundled sounds).
/// Files live in `Foyer/Resources/Sounds/<rawValue>.caf|.m4a` and are original
/// to Foyer; when a file is missing a system sound is used instead.
enum FoyerSound: String, CaseIterable {
    case altJingle = "alt-jingle"
    case blips
    case chime
    case directions
    case event
    case haptic
    case lock
    case lowBattery = "low-battery"
    case lowPower = "low-power"
    case pad
    case sleep
    case unlock
    case volume

    fileprivate var systemFallback: String {
        switch self {
        case .altJingle, .pad: return "Hero"
        case .blips: return "Pop"
        case .chime, .event: return "Glass"
        case .directions: return "Submarine"
        case .haptic, .volume: return "Tink"
        case .lock, .unlock: return "Morse"
        case .lowBattery, .lowPower: return "Basso"
        case .sleep: return "Purr"
        }
    }
}

@MainActor
enum SoundPlayer {
    private static var players: [FoyerSound: AVAudioPlayer] = [:]

    static func play(_ sound: FoyerSound, volume: Float = 1) {
        if let player = player(for: sound) {
            player.volume = volume
            player.currentTime = 0
            player.play()
        } else {
            NSSound(named: NSSound.Name(sound.systemFallback))?.play()
        }
    }

    private static func player(for sound: FoyerSound) -> AVAudioPlayer? {
        if let p = players[sound] { return p }
        let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf")
            ?? Bundle.main.url(forResource: sound.rawValue, withExtension: "m4a")
        guard let url, let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.prepareToPlay()
        players[sound] = p
        return p
    }
}
