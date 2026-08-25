import Foundation

/// Orchestrator. Runs entirely on the main queue (the timer and the control
/// server both hop here), so its state needs no locking.
final class Controller {
    let sessions = SessionManager()
    let power = PowerController()

    private var config: Config
    private var mode: Mode
    private var timerUntil: Date?
    private var thermalPaused = false
    private var lastDecision = Decision(awake: false, deep: false, reason: "off")
    private(set) var lastPower = PowerReading(onBattery: false, percent: nil)
    private(set) var activeSessions = 0

    var onChange: (() -> Void)?

    init() {
        config = loadConfig()
        // 'timer' is transient; a fresh launch lands on 'off'.
        mode = config.mode == .timer ? .off : config.mode
    }

    // MARK: status for the menu / onboarding

    var currentMode: Mode { mode }
    var decision: Decision { lastDecision }
    var onBattery: Bool { lastPower.onBattery }
    var batteryPercent: Int? { lastPower.percent }
    var activeSessionCount: Int { activeSessions }
    var notificationsEnabled: Bool { config.notifications }
    var timerMinutesLeft: Int {
        guard mode == .timer, let until = timerUntil else { return 0 }
        return max(0, Int((until.timeIntervalSinceNow / 60).rounded(.up)))
    }
    var setupComplete: Bool {
        ProcessInfo.processInfo.environment["CLAWAKE_ASSUME_SETUP"] == "1" || helperInstalled()
    }
    var hooksConnected: Bool { claudeHooksInstalled() }

    // MARK: mutations

    func setMode(_ m: Mode, minutes: Int? = nil) {
        if m == .timer {
            timerUntil = Date().addingTimeInterval(Double(minutes ?? 30) * 60)
            mode = .timer
        } else {
            mode = m
            timerUntil = nil
            config.mode = m
            saveConfig(config)
        }
        tick()
    }

    func toggleNotifications() {
        config.notifications.toggle()
        saveConfig(config)
        tick()
    }

    func addSession(_ id: String, transcript: String?) {
        sessions.add(id: id, transcriptPath: transcript)
        tick()
    }

    func removeSession(_ id: String) {
        sessions.remove(id: id)
        tick()
    }

    // MARK: the loop

    func tick() {
        let now = Date()
        if mode == .timer, timerUntil == nil || now >= timerUntil! {
            mode = .off
            timerUntil = nil
        }

        let timeout = Double(config.session_timeout_minutes) * 60
        activeSessions = sessions.activeCount(timeout: timeout, now: now)
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
                    now: now.timeIntervalSince1970,
                    mode: mode,
                    timerUntil: timerUntil?.timeIntervalSince1970,
                    activeSessions: activeSessions,
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

    func connectClaude() -> Bool {
        let ok = installClaudeHooks()
        tick()
        return ok
    }

    func shutdown() {
        power.releaseAll()
    }
}
