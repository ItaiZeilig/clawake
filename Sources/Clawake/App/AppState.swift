import Combine
import Foundation
import ServiceManagement
import ClawakeCore

/// Orchestrator + observable app state for the SwiftUI panels. Runs on the main
/// queue, so its state needs no locking.
final class AppState: ObservableObject {
    let power = PowerController()

    private var config: Config
    private var mode: Mode
    private var thermalPaused = false
    private var lastReason = "off"

    /// Auto-off timer. When set, `tick()` flips the app to Off once the deadline
    /// passes. It is a live session concept, not persisted: quitting ends it.
    /// Minutes for each pill; index 0 ("Until off") means no countdown.
    static let timerOptions = [0, 30, 60, 120]
    private var timerDeadline: Date?

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

    // Screen-lock feature state. In the enterprise build the app never prevents
    // locking and the toggle is hidden; `isEnterprise` gates both.
    @Published private(set) var preventLockOn = true
    @Published private(set) var isEnterprise = false

    // Settings mirrors (so the Settings panel reads live values).
    @Published private(set) var pauseOnLowBattery = true
    @Published private(set) var batteryThreshold = 15
    @Published private(set) var onlyOnAC = false
    @Published private(set) var thermalProtect = true
    @Published private(set) var thermalCritical = false  // false = "Hot", true = "Very hot"

    @Published private(set) var didOnboard = false

    // Auto-off timer mirrors for the UI. `timerRemaining` is "" when no countdown
    // is running; `timerSelectionIndex` is the selected pill in Settings.
    @Published private(set) var timerRemaining = ""
    @Published private(set) var timerSelectionIndex = 0

    /// Extra callback for the AppKit status-item icon (SwiftUI observes directly).
    var onChange: (() -> Void)?

    init() {
        config = loadConfig()
        mode = config.mode
        isEnterprise = (Bundle.main.infoDictionary?["ClawakeEnterprise"] as? Bool) ?? false
        syncMirrors()
    }

    // MARK: mutations

    func setOn(_ on: Bool) { setMode(on ? .on : .off) }

    func setMode(_ m: Mode) {
        mode = m
        config.mode = m
        // Turning off by hand also cancels any running auto-off timer.
        if m == .off { clearTimer() }
        saveConfig(config)
        tick()
    }

    /// Pick an auto-off duration. Index into `timerOptions`; 0 means "Until off"
    /// (no countdown). Choosing a real duration also turns the app on, since the
    /// point is to keep the Mac awake for that long.
    func setTimer(index: Int) {
        guard AppState.timerOptions.indices.contains(index) else { return }
        timerSelectionIndex = index
        let minutes = AppState.timerOptions[index]
        if minutes <= 0 {
            timerDeadline = nil
        } else {
            timerDeadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
            mode = .on
            config.mode = .on
            saveConfig(config)
        }
        tick()
    }

    private func clearTimer() {
        timerDeadline = nil
        timerSelectionIndex = 0
    }

    /// Turn the lid-closed setting on or off. Turning it on does NOT install the
    /// helper — call `installLidHelper()` for that; here we just record the wish
    /// so the panel can show "needs approval".
    func setLidClosedWanted(_ on: Bool) {
        config.lidClosed = on
        saveConfig(config)
        tick()
    }

    /// Register the privileged daemon. macOS may require the user to enable it in
    /// Login Items; if so, open that pane. Completes true once it is enabled.
    func approveLid(completion: @escaping (Bool) -> Void) {
        let status = power.helper.register()
        if status == .requiresApproval {
            power.helper.openLoginItemsSettings()
        }
        tick()
        completion(status == .enabled)
    }

    func helperReady() -> Bool { power.helperEnabled() }

    /// Standard build only: turn the "don't lock the screen" option on or off.
    func setPreventLock(_ on: Bool) {
        config.preventLock = on
        saveConfig(config)
        tick()
    }

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
        // Auto-off timer: once the deadline passes, flip to Off before deciding.
        // Done inline (not via setMode) to avoid re-entering tick().
        if let deadline = timerDeadline, Date() >= deadline {
            clearTimer()
            mode = .off
            config.mode = .off
            saveConfig(config)
        }

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
        let lidApproved = power.helperEnabled()
        let lidActive = config.lidClosed && lidApproved
        let minPercent = config.pauseOnLowBattery ? config.battery.min_percent : 0

        let decision = decide(
            DecideInput(
                mode: mode, onBattery: p.onBattery, batteryPercent: p.percent,
                minPercent: minPercent, onlyOnAC: config.battery.only_on_ac,
                thermalPaused: thermalPaused, lidClosed: lidActive))

        power.apply(decision)
        // "Don't lock" keeps the display on so the screen never locks. Never in the
        // enterprise build, and only while the app is actually keeping the Mac awake.
        power.setKeepDisplayOn(decision.awake && !isEnterprise && config.preventLock)
        lastReason = decision.reason

        // Publish UI state.
        awake = decision.awake
        isOn = (mode == .on)
        lidClosedOn = config.lidClosed
        lidApprovalNeeded = config.lidClosed && !lidApproved
        powerText = p.onBattery ? "Battery\(p.percent.map { " \($0)%" } ?? "")" : "AC power"
        thermalText = thermalLabel(thermal)
        thermalLevelRaw = thermal.rawValue
        timerRemaining = timerDeadline.map { formatRemaining(Int($0.timeIntervalSinceNow.rounded())) } ?? ""
        syncMirrors()
        (statusTitle, statusDetail) = describe(decision: decision, lidActive: lidActive)

        onChange?()
    }

    /// Quitting must fully restore normal sleep. Reconcile the real system state
    /// first (the in-memory `deepEngaged` flag can drift, e.g. a failed toggle or a
    /// state left by an older build), then release every layer, so `SleepDisabled`
    /// is never left set after the app exits.
    func shutdown() {
        power.adoptDeepState()
        power.releaseAll()
    }

    /// Fully remove Clawake's footprint: turn off keep-awake, restore normal sleep,
    /// unregister the privileged daemon, and delete the saved settings. Ordering
    /// matters: `releaseAll` resets the deep layer through the daemon while it is
    /// still registered, then we unregister it.
    func uninstall() {
        power.adoptDeepState()      // learn the real SleepDisabled state (this is a fresh process)
        power.releaseAll()          // reset SleepDisabled via the daemon WHILE it is still registered
        power.helper.unregister()   // then remove the privileged daemon registration
        try? FileManager.default.removeItem(at: Paths.configDir)
    }

    // MARK: helpers

    private func syncMirrors() {
        mode = config.mode
        isOn = (mode == .on)
        lidClosedOn = config.lidClosed
        preventLockOn = config.preventLock
        pauseOnLowBattery = config.pauseOnLowBattery
        batteryThreshold = config.battery.min_percent
        onlyOnAC = config.battery.only_on_ac
        thermalProtect = config.thermal.protect
        thermalCritical = (config.thermal.cutoff == "critical")
        didOnboard = config.didOnboard
    }

    private func formatRemaining(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return "\(h)h \(m)m left" }
        if m > 0 { return "\(m)m left" }
        return "under a minute left"
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

extension AppState {
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
