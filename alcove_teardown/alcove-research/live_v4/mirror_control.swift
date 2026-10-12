import CoreGraphics
import Foundation

func reportDisplays(_ label: String) {
    let mainDisplay = CGMainDisplayID()
    var displayIDs = [CGDirectDisplayID](repeating: 0, count: 32)
    var displayCount: UInt32 = 0
    let result = CGGetActiveDisplayList(
        UInt32(displayIDs.count),
        &displayIDs,
        &displayCount
    )
    let activeIDs = Array(displayIDs.prefix(Int(displayCount)))

    print("\(label) timestamp=\(ISO8601DateFormatter().string(from: Date()))")
    print("main_display_id=\(mainDisplay)")
    print("active_display_ids=\(activeIDs)")
    print("CGGetActiveDisplayList=\(result.rawValue)")
    for displayID in activeIDs {
        print(
            "display_id=\(displayID) " +
            "in_mirror_set=\(CGDisplayIsInMirrorSet(displayID)) " +
            "mirrors_display_id=\(CGDisplayMirrorsDisplay(displayID))"
        )
    }
}

func configureMirror(displayID: CGDirectDisplayID, targetID: CGDirectDisplayID) -> Int32 {
    var configuration: CGDisplayConfigRef?
    let beginResult = CGBeginDisplayConfiguration(&configuration)
    guard beginResult == .success, let configuration else {
        fputs("CGBeginDisplayConfiguration failed: \(beginResult.rawValue)\n", stderr)
        return beginResult.rawValue
    }

    let configureResult = CGConfigureDisplayMirrorOfDisplay(
        configuration,
        displayID,
        targetID
    )
    guard configureResult == .success else {
        fputs(
            "CGConfigureDisplayMirrorOfDisplay failed: \(configureResult.rawValue)\n",
            stderr
        )
        CGCancelDisplayConfiguration(configuration)
        return configureResult.rawValue
    }

    let completeResult = CGCompleteDisplayConfiguration(configuration, .forSession)
    guard completeResult == .success else {
        fputs(
            "CGCompleteDisplayConfiguration failed: \(completeResult.rawValue)\n",
            stderr
        )
        return completeResult.rawValue
    }
    return CGError.success.rawValue
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let action = arguments.first else {
    fputs("usage: mirror_control status [label] | on <virtual-display-id> | off <virtual-display-id>\n", stderr)
    exit(64)
}

switch action {
case "status":
    reportDisplays(arguments.count > 1 ? arguments[1] : "status")
case "on", "off":
    guard arguments.count > 1, let displayID = CGDirectDisplayID(arguments[1]) else {
        fputs("usage: mirror_control \(action) <virtual-display-id>\n", stderr)
        exit(64)
    }
    reportDisplays("before_\(action)")
    let targetID = action == "on" ? CGMainDisplayID() : kCGNullDirectDisplay
    let result = configureMirror(displayID: displayID, targetID: targetID)
    guard result == CGError.success.rawValue else { exit(1) }
    reportDisplays("after_\(action)")
default:
    fputs("unknown action: \(action)\n", stderr)
    exit(64)
}
