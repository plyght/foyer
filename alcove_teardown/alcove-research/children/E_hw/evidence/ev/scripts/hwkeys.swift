// usage: hwkeys <keytype> [count] [flagsHex]   keytype: 0 soundUp 1 soundDown 2 brightUp 3 brightDown 7 mute 21 illumUp 22 illumDown
import Cocoa
let args = CommandLine.arguments
let key = Int32(args.count > 1 ? args[1] : "2")!
let count = args.count > 2 ? Int(args[2])! : 1
let flags = args.count > 3 ? UInt(args[3], radix: 16)! : 0
func post(_ down: Bool) {
    let d1 = Int((key << 16) | ((down ? 0xa : 0xb) << 8))
    let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: flags), timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, subtype: 8, data1: d1, data2: -1)!
    ev.cgEvent!.post(tap: .cghidEventTap)
}
for i in 0..<count { post(true); usleep(20000); post(false); if i < count-1 { usleep(150000) } }
print("posted key \(key) x\(count) flags 0x\(String(flags, radix:16))")
