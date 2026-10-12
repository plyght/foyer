import Cocoa
import CoreGraphics

// usage:
//  evt move X Y
//  evt click X Y
//  evt swipe X Y dx dy steps msPerStep [momentum]   -- trackpad-like scroll gesture with phases
//  evt wheel X Y dx dy                               -- single line-based scroll wheel event (no phases)
//  evt key sound_up|sound_down|mute|play|next|prev|bright_up|bright_down [count] [ms]
//  evt hover X Y ms                                   -- move and dwell

let args = CommandLine.arguments
func post(_ e: CGEvent?) { e?.post(tap: .cghidEventTap) }
func sleepMs(_ ms: Double) { usleep(useconds_t(ms * 1000)) }
func now() -> Double { return Date().timeIntervalSince1970 }
func log(_ s: String) { print(String(format: "%.3f %@", now(), s)); fflush(stdout) }

func mediaKey(_ key: Int32, down: Bool) {
    let flags: UInt = down ? 0xa00 : 0xb00
    let data1 = Int((key << 16) | Int32(flags))
    let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00), timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
    ev?.cgEvent?.post(tap: .cghidEventTap)
}

let cmd = args.count > 1 ? args[1] : ""
switch cmd {
case "move":
    let p = CGPoint(x: Double(args[2])!, y: Double(args[3])!)
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
    log("move \(p)")
case "hover":
    let p = CGPoint(x: Double(args[2])!, y: Double(args[3])!)
    let ms = Double(args[4]) ?? 1000
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
    log("hover-start \(p)")
    sleepMs(ms)
    log("hover-end")
case "click":
    let p = CGPoint(x: Double(args[2])!, y: Double(args[3])!)
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
    sleepMs(50)
    log("click-down \(p)")
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left))
    sleepMs(40)
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left))
    log("click-up")
case "swipeseq":
    // swipeseq X Y "dx:dy,dx:dy,..." msPerStep  -> one continuous gesture with arbitrary per-step deltas (for reversal tests)
    let p = CGPoint(x: Double(args[2])!, y: Double(args[3])!)
    let msPer = Double(args[5]) ?? 16
    let stepsArr = args[4].split(separator: ",").map { s -> (Double, Double) in
        let parts = s.split(separator: ":"); return (Double(parts[0])!, Double(parts[1])!) }
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
    sleepMs(100)
    func scroll2(_ sdx: Double, _ sdy: Double, phase: UInt32) {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(sdy.rounded()), wheel2: Int32(sdx.rounded()), wheel3: 0)!
        e.location = p
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase))
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: sdy)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: sdx)
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(sdy.rounded()))
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(sdx.rounded()))
        post(e)
    }
    scroll2(0, 0, phase: 128); sleepMs(msPer)
    var cx = 0.0, cy = 0.0
    for (i, st) in stepsArr.enumerated() {
        scroll2(st.0, st.1, phase: i == 0 ? 1 : 2); cx += st.0; cy += st.1
        log("swipeseq step\(i) d=(\(st.0),\(st.1)) cum=(\(cx),\(cy))")
        sleepMs(msPer)
    }
    scroll2(0, 0, phase: 4)
    log("swipeseq ended cum=(\(cx),\(cy))")
case "wheel":
    let p = CGPoint(x: Double(args[2])!, y: Double(args[3])!)
    let dx = Int32(args[4])!, dy = Int32(args[5])!
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
    sleepMs(50)
    let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
    e?.location = p
    log("wheel dx=\(dx) dy=\(dy)")
    post(e)
case "swipe":
    // trackpad-like gesture: total dx,dy pixels over N steps, with scroll phases
    let p = CGPoint(x: Double(args[2])!, y: Double(args[3])!)
    let dx = Double(args[4])!, dy = Double(args[5])!
    let steps = Int(args[6]) ?? 10
    let msPer = Double(args[7]) ?? 16
    let momentum = args.count > 8 && args[8] == "momentum"
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
    sleepMs(100)
    func scroll(_ sdx: Double, _ sdy: Double, phase: UInt32, mphase: UInt32) {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(sdy.rounded()), wheel2: Int32(sdx.rounded()), wheel3: 0)!
        e.location = p
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase))
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(mphase))
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: sdy)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: sdx)
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(sdy.rounded()))
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(sdx.rounded()))
        post(e)
    }
    // kCGScrollPhaseBegan=1, Changed=2, Ended=4, Cancelled=8, MayBegin=128
    scroll(0, 0, phase: 128, mphase: 0)
    log("swipe mayBegin")
    sleepMs(msPer)
    scroll(dx/Double(steps), dy/Double(steps), phase: 1, mphase: 0)
    log("swipe began step1 dx=\(dx/Double(steps)) dy=\(dy/Double(steps))")
    sleepMs(msPer)
    var cum = (dx/Double(steps), dy/Double(steps))
    for i in 1..<steps {
        scroll(dx/Double(steps), dy/Double(steps), phase: 2, mphase: 0)
        cum.0 += dx/Double(steps); cum.1 += dy/Double(steps)
        log("swipe changed step\(i+1) cum=\(cum)")
        sleepMs(msPer)
    }
    scroll(0, 0, phase: 4, mphase: 0)
    log("swipe ended total=\(cum)")
    if momentum {
        sleepMs(msPer)
        // kCGMomentumScrollPhaseBegin=1, Continue=2, End=3
        scroll(dx/Double(steps), dy/Double(steps), phase: 0, mphase: 1)
        var m = dx/Double(steps), my = dy/Double(steps)
        for _ in 0..<8 { sleepMs(msPer); m *= 0.7; my *= 0.7; scroll(m, my, phase: 0, mphase: 2) }
        sleepMs(msPer); scroll(0, 0, phase: 0, mphase: 3)
        log("momentum ended")
    }
case "key":
    let map: [String: Int32] = ["sound_up": 0, "sound_down": 1, "bright_up": 2, "bright_down": 3, "mute": 7, "play": 16, "next": 17, "prev": 18, "fast": 19, "rewind": 20]
    let k = map[args[2]]!
    let count = args.count > 3 ? Int(args[3])! : 1
    let ms = args.count > 4 ? Double(args[4])! : 100
    for i in 0..<count {
        mediaKey(k, down: true); sleepMs(10); mediaKey(k, down: false)
        log("key \(args[2]) #\(i+1)")
        if i < count-1 { sleepMs(ms) }
    }
default:
    print("unknown cmd")
}
