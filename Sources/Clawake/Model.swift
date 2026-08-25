import Foundation

// MARK: - Modes and the pure decision function (ported from decide.ts)

enum Mode: String, Codable, CaseIterable {
    case sessions, always, timer, off
}

struct Decision: Equatable {
    let awake: Bool
    let deep: Bool
    let reason: String
}

struct DecideInput {
    var now: Double            // epoch seconds
    var mode: Mode
    var timerUntil: Double?    // epoch seconds
    var activeSessions: Int
    var onBattery: Bool
    var batteryPercent: Int?
    var minPercent: Int
    var onlyOnAC: Bool
    var thermalPaused: Bool
}

func decide(_ i: DecideInput) -> Decision {
    var want = false
    var reason = "off"
    switch i.mode {
    case .off:
        want = false; reason = "off"
    case .always:
        want = true; reason = "always"
    case .sessions:
        want = i.activeSessions > 0
        reason = want ? "sessions-active" : "sessions-idle"
    case .timer:
        if let until = i.timerUntil, i.now < until {
            want = true; reason = "timer"
        } else {
            want = false; reason = "timer-expired"
        }
    }

    if !want { return Decision(awake: false, deep: false, reason: reason) }

    // Battery floor.
    if i.onBattery, let p = i.batteryPercent, i.minPercent > 0, p <= i.minPercent {
        return Decision(awake: false, deep: false, reason: "battery-low")
    }
    if i.onBattery && i.onlyOnAC {
        return Decision(awake: false, deep: false, reason: "battery-only-ac")
    }
    // Thermal safety (already latched with hysteresis).
    if i.thermalPaused {
        return Decision(awake: false, deep: false, reason: "thermal")
    }
    // Lid-closed is always on whenever we keep awake.
    return Decision(awake: true, deep: true, reason: reason)
}

// MARK: - Thermal (ported from thermal.ts)

enum ThermalLevel: Int {
    case unknown = -1, nominal = 0, fair = 1, serious = 2, critical = 3
}

func atOrAboveCutoff(_ state: ThermalLevel, _ cutoff: ThermalLevel) -> Bool {
    if state == .unknown { return false }
    let cutoffRank = (cutoff == .serious || cutoff == .critical) ? cutoff.rawValue : ThermalLevel.serious.rawValue
    return state.rawValue >= cutoffRank
}

/// Hysteresis latch: enter at the cutoff, leave only on a definite `nominal`.
func nextThermalPaused(_ prev: Bool, _ state: ThermalLevel, _ cutoff: ThermalLevel) -> Bool {
    if prev { return state != .nominal }
    return atOrAboveCutoff(state, cutoff)
}

func thermalCutoff(from string: String) -> ThermalLevel {
    return string == "critical" ? .critical : .serious
}

// MARK: - Battery (ported from battery.ts)

struct PowerReading {
    var onBattery: Bool
    var percent: Int?
}

func parsePmsetBatt(_ output: String) -> PowerReading {
    let onBattery = output.contains("'Battery Power'")
    var percent: Int?
    if let range = output.range(of: #"[0-9]+%"#, options: .regularExpression) {
        let token = output[range].dropLast()  // strip the % sign
        if let v = Int(token) { percent = min(100, max(0, v)) }
    }
    return PowerReading(onBattery: onBattery, percent: percent)
}
