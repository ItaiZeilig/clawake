import Combine
import Foundation

/// Orchestrator + observable app state for the SwiftUI panels. Runs on the main
/// queue, so its state needs no locking.
final class Controller: ObservableObject {
    let power = PowerController()

    private var config: Config
    private var mode: Mode
    private var thermalPaused = false
    private var lastReason = "off"

    // Published UI state (read by the popover / onboarding).
    @Published private(set) var awake = false
    @Published private(set) var isOn = false
    @Published private(set) var statusTitle = "Sleeping normally"
    @Published private(set) var statusDetail = ""
    @Published private(set) var powerText = ""
    @Published private(set) var setupComplete = false
    @Published private(set) var notificationsEnabled = true

    /// Extra callback for the AppKit status-item icon (SwiftUI observes directly).
    var onChange: (() -> Void)?

    init() {
        config = loadConfig()
        mode = config.mode
        notificationsEnabled = config.notifications
        setupComplete = computeSetupComplete()
    }

    // MARK: mutations

    func setOn(_ on: Bool) { setMode(on ? .on : .off) }

    func setMode(_ m: Mode) {
        mode = m
        config.mode = m
        saveConfig(config)
        tick()
    }

    func toggleNotifications() {
        config.notifications.toggle()
        saveConfig(config)
        tick()
    }

    func installLidHelper() -> Bool {
        let ok = installHelper()
        tick()
        return ok
    }

    func helperReady() -> Bool { helperInstalled() }

    // MARK: the loop

    func tick() {
        let p = readPower()
        let cutoff = thermalCutoff(from: config.thermal.cutoff)
        thermalPaused =
            config.thermal.protect
            ? nextThermalPaused(thermalPaused, readThermal(), cutoff)
            : false

        let complete = computeSetupComplete()
        let decision: Decision =
            complete
            ? decide(
                DecideInput(
                    mode: mode, onBattery: p.onBattery, batteryPercent: p.percent,
                    minPercent: config.battery.min_percent, onlyOnAC: config.battery.only_on_ac,
                    thermalPaused: thermalPaused))
            : Decision(awake: false, deep: false, reason: "setup")

        power.apply(decision)
        lastReason = decision.reason

        // Publish UI state.
        setupComplete = complete
        awake = decision.awake
        isOn = (mode == .on)
        notificationsEnabled = config.notifications
        powerText = p.onBattery ? "Battery\(p.percent.map { " \($0)%" } ?? "")" : "AC power"
        (statusTitle, statusDetail) = describe(decision: decision, complete: complete)

        onChange?()
    }

    func shutdown() { power.releaseAll() }

    // MARK: helpers

    private func computeSetupComplete() -> Bool {
        ProcessInfo.processInfo.environment["CLAWAKE_ASSUME_SETUP"] == "1" || helperInstalled()
    }

    private func describe(decision: Decision, complete: Bool) -> (String, String) {
        if !complete { return ("Setup needed", "Finish setup to start") }
        if decision.awake { return ("Keeping your Mac awake", "The lid can stay closed") }
        switch decision.reason {
        case "thermal": return ("Paused to cool down", "Your Mac is running hot")
        case "battery-low": return ("Sleeping to save battery", "Battery is low")
        case "battery-only-ac": return ("Sleeping on battery", "Set to keep awake on AC only")
        default: return ("Sleeping normally", "Your Mac can sleep")
        }
    }
}
