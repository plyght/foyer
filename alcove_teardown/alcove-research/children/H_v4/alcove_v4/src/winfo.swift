import Foundation
import CoreGraphics
// prints Alcove on-screen windows: id,layer,x,y,w,h
let opts: CGWindowListOption = [.optionOnScreenOnly]
let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as! [[String: Any]]
var out: [String] = []
for w in list {
    guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "Alcove" else { continue }
    let id = w[kCGWindowNumber as String] as! Int
    let layer = w[kCGWindowLayer as String] as! Int
    let b = w[kCGWindowBounds as String] as! [String: Any]
    let x = b["X"] as! Double, y = b["Y"] as! Double, wd = b["Width"] as! Double, h = b["Height"] as! Double
    out.append("\(id):\(layer):\(Int(x)):\(Int(y)):\(Int(wd))x\(Int(h))")
}
print(out.joined(separator: ";"))
