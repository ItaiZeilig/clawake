import AppKit

func carIcon(active: Bool) -> NSImage? {
    let name = active ? "car-active" : "car-idle"
    if let url = Bundle.main.url(forResource: name, withExtension: "png"),
       let img = NSImage(contentsOf: url) {
        img.size = NSSize(width: 20, height: 20)
        return img
    }
    return nil
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let controller = Controller()
    let server = ControlServer()
    var statusItem: NSStatusItem!
    let menu = NSMenu()
    var timer: Timer?
    var onboarding: OnboardingController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // menu-bar only, no dock

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = carIcon(active: false)
            btn.target = self
            btn.action = #selector(statusClicked)
        }
        menu.delegate = self

        controller.onChange = { [weak self] in self?.refresh() }
        server.onCaffeinate = { [weak self] id in self?.controller.addSession(id, transcript: nil) }
        server.onUncaffeinate = { [weak self] id in self?.controller.removeSession(id) }
        server.start()

        controller.tick()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.controller.tick()
        }

        if !controller.setupComplete { openOnboarding() }
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
        server.stop()
    }

    // Click opens the setup window until setup is done; afterwards it shows the menu.
    @objc func statusClicked() {
        if controller.setupComplete {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            openOnboarding()
        }
    }

    func refresh() {
        statusItem.button?.image = carIcon(active: controller.decision.awake)
        statusItem.button?.toolTip = "Clawake: " + statusLine()
    }

    func openOnboarding() {
        if onboarding == nil { onboarding = OnboardingController(controller: controller) }
        onboarding?.show()
    }

    // MARK: - status text

    private func statusLine() -> String {
        let d = controller.decision
        if !d.awake {
            if d.reason == "thermal" { return "Paused, Mac is hot" }
            return controller.currentMode == .off ? "Off, sleep allowed" : "Sleep allowed"
        }
        switch controller.currentMode {
        case .timer: return "Awake, \(controller.timerMinutesLeft) min left"
        case .always: return "Awake, always"
        default:
            let n = controller.activeSessionCount
            return "Awake, \(n) Claude session\(n == 1 ? "" : "s")"
        }
    }

    private func powerLine() -> String {
        let src = controller.onBattery ? "Battery" : "AC power"
        if let p = controller.batteryPercent { return "\(src), \(p)%" }
        return src
    }

    // MARK: - menu (rebuilt each time it opens)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addDisabled(statusLine())
        addDisabled(powerLine())
        menu.addItem(.separator())

        addMode("Follow Claude sessions", .sessions)
        addMode("Always awake", .always)
        addMode("Off (allow sleep)", .off)
        menu.addItem(.separator())

        let timerItem = NSMenuItem(title: "Keep awake for…", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()
        for m in [15, 30, 60, 120] {
            let label = m < 60 ? "\(m) minutes" : "\(m / 60) hour\(m == 60 ? "" : "s")"
            let it = NSMenuItem(title: label, action: #selector(timerSelected(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = m
            timerMenu.addItem(it)
        }
        timerItem.submenu = timerMenu
        menu.addItem(timerItem)
        menu.addItem(.separator())

        // Setup submenu
        let setupItem = NSMenuItem(title: "Setup", action: nil, keyEquivalent: "")
        let setupMenu = NSMenu()
        let openIt = NSMenuItem(title: "Open Setup window…", action: #selector(openSetup), keyEquivalent: "")
        openIt.target = self
        setupMenu.addItem(openIt)
        setupMenu.addItem(.separator())
        if helperInstalled() {
            setupMenu.addItem(disabledItem("✓  Lid-closed: password-free"))
        } else {
            let it = NSMenuItem(title: "Make lid-closed password-free…", action: #selector(installHelperAction), keyEquivalent: "")
            it.target = self
            setupMenu.addItem(it)
        }
        if controller.hooksConnected {
            setupMenu.addItem(disabledItem("✓  Claude Code connected"))
        } else {
            let it = NSMenuItem(title: "Connect Claude Code…", action: #selector(connectClaudeAction), keyEquivalent: "")
            it.target = self
            setupMenu.addItem(it)
        }
        let notif = NSMenuItem(title: "Notifications", action: #selector(toggleNotificationsAction), keyEquivalent: "")
        notif.target = self
        notif.state = controller.notificationsEnabled ? .on : .off
        setupMenu.addItem(notif)
        setupItem.submenu = setupMenu
        menu.addItem(setupItem)
        menu.addItem(.separator())

        addDisabled("Clawake v\(appVersion())")
        let quitIt = NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q")
        quitIt.target = self
        menu.addItem(quitIt)
    }

    private func addDisabled(_ title: String) { menu.addItem(disabledItem(title)) }
    private func disabledItem(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }
    private func addMode(_ title: String, _ mode: Mode) {
        let it = NSMenuItem(title: title, action: #selector(modeSelected(_:)), keyEquivalent: "")
        it.target = self
        it.representedObject = mode.rawValue
        it.state = controller.currentMode == mode ? .on : .off
        menu.addItem(it)
    }

    // MARK: - actions

    @objc func modeSelected(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let m = Mode(rawValue: raw) {
            controller.setMode(m)
        }
    }
    @objc func timerSelected(_ sender: NSMenuItem) {
        if let mins = sender.representedObject as? Int { controller.setMode(.timer, minutes: mins) }
    }
    @objc func connectClaudeAction() { _ = controller.connectClaude() }
    @objc func toggleNotificationsAction() { controller.toggleNotifications() }
    @objc func installHelperAction() { _ = controller.installLidHelper() }
    @objc func openSetup() { openOnboarding() }
    @objc func quitAction() { NSApp.terminate(nil) }
}

func appVersion() -> String {
    (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
}
