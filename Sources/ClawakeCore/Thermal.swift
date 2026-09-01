import Foundation

// MARK: - Thermal

public enum ThermalLevel: Int {
    case unknown = -1, nominal = 0, fair = 1, serious = 2, critical = 3
}

public func atOrAboveCutoff(_ state: ThermalLevel, _ cutoff: ThermalLevel) -> Bool {
    if state == .unknown { return false }
    let cutoffRank = (cutoff == .serious || cutoff == .critical) ? cutoff.rawValue : ThermalLevel.serious.rawValue
    return state.rawValue >= cutoffRank
}

/// Hysteresis latch: enter at the cutoff, leave only on a definite `nominal`.
public func nextThermalPaused(_ prev: Bool, _ state: ThermalLevel, _ cutoff: ThermalLevel) -> Bool {
    if prev { return state != .nominal }
    return atOrAboveCutoff(state, cutoff)
}

public func thermalCutoff(from string: String) -> ThermalLevel {
    return string == "critical" ? .critical : .serious
}

/// Human-friendly name for the current temperature, shown in the panel.
public func thermalLabel(_ level: ThermalLevel) -> String {
    switch level {
    case .nominal: return "Normal"
    case .fair: return "Warm"
    case .serious: return "Hot"
    case .critical: return "Very hot"
    case .unknown: return "—"
    }
}
