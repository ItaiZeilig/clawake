import Foundation

/// Orchestrator. Runs on the main queue, so its state needs no locking.
final class Controller {
    let power = PowerController()

    private var config: Config
    private var mode: Mode
    private var thermalPaused = false
    private var lastDecision = Decision(awake: false, deep: false, reason: "off")
    private(set) var lastPower = PowerReading(onBattery: false, percent: nil)

    var onChange: (() -> Void)?

    init() {
        config = loadConfig()
        mode = config.mode
    }

    // MARK: status for the menu / onboarding

    var currentMode: Mode { mode }
    var decision: Decision { lastDecision }
    var onBattery: Bool { lastPower.onBattery }
    var batteryPercent: Int? { lastPower.percent }
    var notificationsEnabled: Bool { config.notifications }
    var setupComplete: Bool {
        ProcessInfo.processInfo.environment["CLAWAKE_ASSUME_SETUP"] == "1" || helperInstalled()
    }

    // MARK: mutations

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

    // MARK: the loop

    func tick() {
        lastPower = readPower()
        let cutoff = thermalCutoff(from: config.thermal.cutoff)
        thermalPaused =
            config.thermal.protect
            ? nextThermalPaused(thermalPaused, readThermal(), cutoff)
            : false

        let decision: Decision
        if !setupComplete {
            decision = Decision(awake: false, deep: false, reason: "setup")
        } else {
            decision = decide(
                DecideInput(
                    mode: mode,
                    onBattery: lastPower.onBattery,
                    batteryPercent: lastPower.percent,
                    minPercent: config.battery.min_percent,
                    onlyOnAC: config.battery.only_on_ac,
                    thermalPaused: thermalPaused
                ))
        }
        lastDecision = decision
        power.apply(decision)
        onChange?()
    }

    func installLidHelper() -> Bool {
        let ok = installHelper()
        tick()
        return ok
    }

    func shutdown() {
        power.releaseAll()
    }
}
