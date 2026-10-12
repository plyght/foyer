import Foundation
import CoreGraphics

// usage: swipe <x> <y> <dir: left|right|up|down> <distancePx> [steps=12] [stepIntervalMs=8] [reverseAt=0]
// Posts a trackpad-style continuous scroll gesture (phase began/changed/ended) at (x,y) with total pixel distance.
// reverseAt > 0: move 'reverseAt' px in dir, then 'distance' px back the opposite way (to probe reset thresholds).
let args = CommandLine.arguments
guard args.count >= 5, let x = Double(args[1]), let y = Double(args[2]), let dist = Double(args[4]) else {
    FileHandle.standardError.write("usage: swipe x y dir dist [steps] [intervalMs] [reverseAt]\n".data(using: .utf8)!)
    exit(2)
}
let dir = args[3]
let steps = args.count > 5 ? Int(args[5])! : 12
let intervalMs = args.count > 6 ? Double(args[6])! : 8
let reverseAt = args.count > 7 ? Double(args[7])! : 0
let thirdLeg = args.count > 8 ? Double(args[8])! : 0  // optional: after reversing, go 'thirdLeg' px in the original direction again

let pt = CGPoint(x: x, y: y)
func post(_ ev: CGEvent) { ev.location = pt; ev.post(tap: .cghidEventTap) }

func scroll(dx: Int32, dy: Int32, phase: Int64, momentum: Int64 = 0) {
    guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
    e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
    e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(dy))
    e.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(dx))
    e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(dy))
    e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(dx))
    post(e)
}

// Move the pointer to the target so the gesture lands in Alcove's hover region.
if let mv = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left) { mv.post(tap: .cghidEventTap) }
usleep(150_000)

// Direction sign conventions: positive dy = scroll content down (finger moves up on natural? no: with "natural scrolling" OFF,
// positive wheel1 delta = scroll up). We report raw deltas; the mapping is validated empirically in the report.
var sx: Int32 = 0, sy: Int32 = 0
switch dir {
case "up":    sy = 1
case "down":  sy = -1
case "left":  sx = 1
case "right": sx = -1
default: exit(2)
}

func emit(distance: Double, sgnX: Int32, sgnY: Int32, first: Bool) {
    var sent = 0.0
    let per = distance / Double(steps)
    var acc = 0.0
    for i in 0..<steps {
        acc += per
        let d = Int32((acc - sent).rounded())
        sent += Double(d)
        let phase: Int64 = (first && i == 0) ? 1 /* began */ : 2 /* changed */
        scroll(dx: sgnX * d, dy: sgnY * d, phase: phase)
        usleep(useconds_t(intervalMs * 1000))
    }
}

let t0 = Date()
// kCGScrollPhaseBegan = 1, Changed = 2, Ended = 4, Cancelled = 8, MayBegin = 128
if reverseAt > 0 {
    emit(distance: reverseAt, sgnX: sx, sgnY: sy, first: true)
    emit(distance: dist, sgnX: -sx, sgnY: -sy, first: false)
    if thirdLeg > 0 { emit(distance: thirdLeg, sgnX: sx, sgnY: sy, first: false) }
} else {
    emit(distance: dist, sgnX: sx, sgnY: sy, first: true)
}
scroll(dx: 0, dy: 0, phase: 4)
let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
print("\(f.string(from: t0)),\(dir),\(Int(dist)),\(Int(reverseAt)),\(steps),\(Int(intervalMs)),\(Int(thirdLeg))")
