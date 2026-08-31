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

    // Published UI state (read by the popover / settings).
    @Published private(set) var awake = false
    @Published private(set) var isOn = false
    @Published private(set) var statusTitle = "Sleeping normally"
    @Published private(set) var statusDetail = ""
    @Published private(set) var powerText = ""
    @Published private(set) var thermalText = "—"
    @Published private(set) var thermalLevelRaw = ThermalLevel.unknown.rawValue

    // Lid-closed feature state.
    @Published private(set) var lidClosedOn = true       // the setting
    @Published private(set) var lidApprovalNeeded = false // wanted, but not approved yet

    // Settings mirrors (so the Settings panel reads live values).
    @Published private(set) var pauseOnLowBattery = true
    @Published private(set) var batteryThreshold = 15
    @Published private(set) var onlyOnAC = false
    @Published private(set) var thermalProtect = true
    @Published private(set) var thermalCritical = false  // false = "Hot", true = "Very hot"

    @Published private(set) var didOnboard = false

    /// Extra callback for the AppKit status-item icon (SwiftUI observes directly).
    var onChange: (() -> Void)?

    init() {
        config = loadConfig()
        mode = config.mode
        syncMirrors()
    }

    // MARK: mutations

    func setOn(_ on: Bool) { setMode(on ? .on : .off) }

    func setMode(_ m: Mode) {
        mode = m
        config.mode = m
        saveConfig(config)
        tick()
    }

    /// Turn the lid-closed setting on or off. Turning it on does NOT install the
    /// helper — call `installLidHelper()` for that; here we just record the wish
    /// so the panel can show "needs approval".
    func setLidClosedWanted(_ on: Bool) {
        config.lidClosed = on
        saveConfig(config)
        tick()
    }

    /// Run the one-time admin approval off the main thread, then refresh on main.
    func approveLid(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global().async {
            let ok = installHelper()
            DispatchQueue.main.async {
                self.tick()
                completion(ok)
            }
        }
    }

    func helperReady() -> Bool { helperInstalled() }

    func setPauseOnLowBattery(_ on: Bool) {
        config.pauseOnLowBattery = on
        saveConfig(config)
        tick()
    }

    func setBatteryThreshold(_ pct: Int) {
        config.battery.min_percent = pct
        saveConfig(config)
        tick()
    }

    func setOnlyOnAC(_ on: Bool) {
        config.battery.only_on_ac = on
        saveConfig(config)
        tick()
    }

    func setThermalProtect(_ on: Bool) {
        config.thermal.protect = on
        saveConfig(config)
        tick()
    }

    func setThermalCritical(_ critical: Bool) {
        config.thermal.cutoff = critical ? "critical" : "serious"
        saveConfig(config)
        tick()
    }

    func markOnboarded() {
        config.didOnboard = true
        saveConfig(config)
        didOnboard = true
    }

    // MARK: the loop

    func tick() {
        let p = readPower()
        let thermal = readThermal()
        let cutoff = thermalCutoff(from: config.thermal.cutoff)
        thermalPaused =
            config.thermal.protect
            ? nextThermalPaused(thermalPaused, thermal, cutoff)
            : false

        // The deep (lid-closed) layer only engages when the user asked for it AND
        // the one-time approval is in place — otherwise we'd trigger a password
        // prompt every cycle.
        let lidApproved = helperInstalled()
        let lidActive = config.lidClosed && lidApproved
        let minPercent = config.pauseOnLowBattery ? config.battery.min_percent : 0

        let decision = decide(
            DecideInput(
                mode: mode, onBattery: p.onBattery, batteryPercent: p.percent,
                minPercent: minPercent, onlyOnAC: config.battery.only_on_ac,
                thermalPaused: thermalPaused, lidClosed: lidActive))

        power.apply(decision)
        lastReason = decision.reason

        // Publish UI state.
        awake = decision.awake
        isOn = (mode == .on)
        lidClosedOn = config.lidClosed
        lidApprovalNeeded = config.lidClosed && !lidApproved
        powerText = p.onBattery ? "Battery\(p.percent.map { " \($0)%" } ?? "")" : "AC power"
        thermalText = thermalLabel(thermal)
        thermalLevelRaw = thermal.rawValue
        syncMirrors()
        (statusTitle, statusDetail) = describe(decision: decision, lidActive: lidActive)

        onChange?()
    }

    func shutdown() { power.releaseAll() }

    // MARK: helpers

    private func syncMirrors() {
        mode = config.mode
        isOn = (mode == .on)
        lidClosedOn = config.lidClosed
        pauseOnLowBattery = config.pauseOnLowBattery
        batteryThreshold = config.battery.min_percent
        onlyOnAC = config.battery.only_on_ac
        thermalProtect = config.thermal.protect
        thermalCritical = (config.thermal.cutoff == "critical")
        didOnboard = config.didOnboard
    }

    private func describe(decision: Decision, lidActive: Bool) -> (String, String) {
        if decision.awake {
            if lidActive { return ("Keeping your Mac awake", "The lid can stay closed") }
            if lidApprovalNeeded { return ("Keeping your Mac awake", "Approve to allow the lid closed") }
            return ("Keeping your Mac awake", "Sleeps when you close the lid")
        }
        switch decision.reason {
        case "thermal": return ("Paused to cool down", "Your Mac is running hot")
        case "battery-low": return ("Sleeping to save battery", "Battery is low")
        case "battery-only-ac": return ("Sleeping on battery", "Set to keep awake on AC only")
        default: return ("Sleeping normally", "Your Mac can sleep")
        }
    }
}

extension Controller {
    /// Fill the published display state directly, for rendering a marketing or
    /// preview image of the real panel. Reads no sensors, writes no config, and
    /// creates no power assertions. Same-file so it can set the private(set) fields.
    func fillForRender(
        isOn: Bool, awake: Bool, statusTitle: String, powerText: String,
        thermalText: String, thermalLevel: ThermalLevel, lidClosedOn: Bool
    ) {
        self.isOn = isOn
        self.awake = awake
        self.statusTitle = statusTitle
        self.powerText = powerText
        self.thermalText = thermalText
        self.thermalLevelRaw = thermalLevel.rawValue
        self.lidClosedOn = lidClosedOn
        self.lidApprovalNeeded = false
    }
}
