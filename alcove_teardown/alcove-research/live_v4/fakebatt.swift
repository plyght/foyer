import CoreFoundation
import Foundation

@_silgen_name("IOPSCreatePowerSource")
private func createPowerSource(_ source: UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32

@_silgen_name("IOPSSetPowerSourceDetails")
private func setPowerSourceDetails(_ source: UnsafeMutableRawPointer, _ details: CFDictionary) -> Int32

@_silgen_name("IOPSReleasePowerSource")
private func releasePowerSource(_ source: UnsafeMutableRawPointer) -> Int32

private struct BatteryState {
    var level = 50
    var state = "battery"
    var charging = false

    var description: String {
        "level=\(level) state=\(state) charging=\(charging ? 1 : 0)"
    }
}

private func parseBoolean(_ value: String) -> Bool? {
    switch value.lowercased() {
    case "1", "true", "yes", "on":
        return true
    case "0", "false", "no", "off":
        return false
    default:
        return nil
    }
}

private func applyArgument(_ name: String, _ value: String, to state: inout BatteryState) -> Bool {
    switch name {
    case "--level", "level":
        guard let level = Int(value), (0...100).contains(level) else { return false }
        state.level = level
        return true
    case "--state", "state":
        guard ["battery", "ac"].contains(value.lowercased()) else { return false }
        state.state = value.lowercased()
        return true
    case "--charging", "charging":
        guard let charging = parseBoolean(value) else { return false }
        state.charging = charging
        return true
    default:
        return false
    }
}

private func resultDescription(_ result: Int32) -> String {
    String(format: "IOReturn=%d (0x%08x)", result, UInt32(bitPattern: result))
}

private var battery = BatteryState()
private var source: UnsafeMutableRawPointer?

let arguments = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < arguments.count {
    let argument = arguments[index]
    if argument == "--help" || argument == "-h" {
        print("Usage: fakebatt [--level 0...100] [--state battery|ac] [--charging 0|1]")
        print("stdin commands: level N | state battery|ac | charging 0|1")
        exit(0)
    }
    guard index + 1 < arguments.count, applyArgument(argument, arguments[index + 1], to: &battery) else {
        fputs("ERROR: invalid argument near \(argument)\n", stderr)
        exit(2)
    }
    index += 2
}

var createdSource: UnsafeMutableRawPointer?
let createResult = createPowerSource(&createdSource)
guard createResult == 0, let createdSource else {
    fputs("IOPSCreatePowerSource failed: \(resultDescription(createResult)); source=\(String(describing: createdSource))\n", stderr)
    exit(1)
}
source = createdSource
print("IOPSCreatePowerSource: success")

private func publish(_ state: BatteryState, to source: UnsafeMutableRawPointer) -> Int32 {
    let batteryMode = state.state == "battery"
    let details: [String: Any] = [
        "Type": "InternalBattery",
        "Name": "InternalBattery-0",
        "Transport Type": "Internal",
        "Is Present": true,
        "Power Source State": batteryMode ? "Battery Power" : "AC Power",
        "Current Capacity": state.level,
        "Max Capacity": 100,
        "Is Charging": state.charging,
        "Is Charged": state.level >= 100,
        "Time to Empty": batteryMode && !state.charging ? max(1, state.level * 3) : -1,
        "Time to Full Charge": state.charging ? max(1, 100 - state.level) * 2 : -1,
        "Power Source ID": 1
    ]
    return setPowerSourceDetails(source, details as NSDictionary as CFDictionary)
}

let initialResult = publish(battery, to: createdSource)
print("IOPSSetPowerSourceDetails initial (\(battery.description)): \(resultDescription(initialResult))")
guard initialResult == 0 else {
    let releaseResult = releasePowerSource(createdSource)
    fputs("IOPSReleasePowerSource: \(resultDescription(releaseResult))\n", stderr)
    exit(1)
}

while let line = readLine() {
    let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
    guard parts.count == 2, applyArgument(parts[0], parts[1], to: &battery) else {
        fputs("ERROR: expected 'level N', 'state battery|ac', or 'charging 0|1'; got: \(line)\n", stderr)
        continue
    }
    let result = publish(battery, to: createdSource)
    print("IOPSSetPowerSourceDetails update (\(battery.description)): \(resultDescription(result))")
}

let releaseResult = releasePowerSource(createdSource)
print("IOPSReleasePowerSource: \(resultDescription(releaseResult))")
