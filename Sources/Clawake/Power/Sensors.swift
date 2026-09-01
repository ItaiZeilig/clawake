import Foundation
import ClawakeCore

// MARK: - Thermal (native, no root, no polling of private sensors)

func readThermal() -> ThermalLevel {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: return .nominal
    case .fair: return .fair
    case .serious: return .serious
    case .critical: return .critical
    @unknown default: return .unknown
    }
}

// MARK: - Battery / power source

func readPower() -> PowerReading {
    let r = runProcess("/usr/bin/pmset", ["-g", "batt"])
    if !r.ok || r.stdout.isEmpty {
        return PowerReading(onBattery: false, percent: nil)
    }
    return parsePmsetBatt(r.stdout)
}
