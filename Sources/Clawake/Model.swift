import Foundation

// MARK: - Modes and the pure decision function (ported from decide.ts)

enum Mode: String, Codable, CaseIterable {
    case on, off
}

struct Decision: Equatable {
    let awake: Bool
    let deep: Bool
    let reason: String
}

struct DecideInput {
    var mode: Mode
    var onBattery: Bool
    var batteryPercent: Int?
    var minPercent: Int
    var onlyOnAC: Bool
    var thermalPaused: Bool
    /// Whether the lid-closed (deep) layer should engage while awake. The caller
    /// passes `false` when the user turned it off, or when it isn't approved yet.
    var lidClosed: Bool
}

func decide(_ i: DecideInput) -> Decision {
    if i.mode == .off {
        return Decision(awake: false, deep: false, reason: "off")
    }
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
    // On. Lid-closed rides along only when the user asked for it and it's approved.
    return Decision(awake: true, deep: i.lidClosed, reason: "on")
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

/// Human-friendly name for the current temperature, shown in the panel.
func thermalLabel(_ level: ThermalLevel) -> String {
    switch level {
    case .nominal: return "Normal"
    case .fair: return "Warm"
    case .serious: return "Hot"
    case .critical: return "Very hot"
    case .unknown: return "—"
    }
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
