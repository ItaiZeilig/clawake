import Foundation

// MARK: - Modes and the pure decision function

public enum Mode: String, Codable, CaseIterable {
    case on, off
}

public struct Decision: Equatable {
    public let awake: Bool
    public let deep: Bool
    public let reason: String

    public init(awake: Bool, deep: Bool, reason: String) {
        self.awake = awake
        self.deep = deep
        self.reason = reason
    }
}

public struct DecideInput {
    public var mode: Mode
    public var onBattery: Bool
    public var batteryPercent: Int?
    public var minPercent: Int
    public var onlyOnAC: Bool
    public var thermalPaused: Bool
    /// Whether the lid-closed (deep) layer should engage while awake. The caller
    /// passes `false` when the user turned it off, or when it isn't approved yet.
    public var lidClosed: Bool

    public init(
        mode: Mode, onBattery: Bool, batteryPercent: Int?, minPercent: Int,
        onlyOnAC: Bool, thermalPaused: Bool, lidClosed: Bool
    ) {
        self.mode = mode
        self.onBattery = onBattery
        self.batteryPercent = batteryPercent
        self.minPercent = minPercent
        self.onlyOnAC = onlyOnAC
        self.thermalPaused = thermalPaused
        self.lidClosed = lidClosed
    }
}

/// The single decision function: off, battery floor, only-on-AC, thermal pause,
/// else awake with `deep = lidClosed`. Pure and side-effect free.
public func decide(_ i: DecideInput) -> Decision {
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
