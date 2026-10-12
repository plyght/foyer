// Synthesize NX_SYSDEFINED (subtype 8) special-key events like the hardware
// volume/brightness/play keys do.  usage: mediakey <volup|voldown|mute|brightup|brightdown|play|next|prev> [repeat]
import Cocoa
let keys: [String: Int32] = ["volup": NX_KEYTYPE_SOUND_UP, "voldown": NX_KEYTYPE_SOUND_DOWN, "mute": NX_KEYTYPE_MUTE,
    "brightup": NX_KEYTYPE_BRIGHTNESS_UP, "brightdown": NX_KEYTYPE_BRIGHTNESS_DOWN,
    "play": NX_KEYTYPE_PLAY, "next": NX_KEYTYPE_NEXT, "prev": NX_KEYTYPE_PREVIOUS]
guard CommandLine.arguments.count > 1, let key = keys[CommandLine.arguments[1]] else { print("bad key"); exit(1) }
let n = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 1 : 1
func post(_ down: Bool) {
    let flags: NSEvent.ModifierFlags = down ? [.init(rawValue: 0xa00)] : [.init(rawValue: 0xb00)]
    let data1 = Int((key << 16) | (down ? 0x0a00 : 0x0b00))
    guard let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1) else { print("no event"); exit(2) }
    ev.cgEvent?.post(tap: .cghidEventTap)
}
for _ in 0..<n { post(true); usleep(20_000); post(false); usleep(80_000) }
print("posted \(CommandLine.arguments[1]) x\(n) via CGEvent.post(.cghidEventTap)")
