import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppState()
    var statusItem: NSStatusItem!
    var popoverController: PopoverController!
    var settings: SettingsController?
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hidden render mode for marketing/preview shots of the real panel.
        if let idx = CommandLine.arguments.firstIndex(of: "--render-panel"),
           idx + 1 < CommandLine.arguments.count {
            renderPanel(to: CommandLine.arguments[idx + 1])
            exit(0)
        }
        if let idx = CommandLine.arguments.firstIndex(of: "--render-settings"),
           idx + 1 < CommandLine.arguments.count {
            renderSettings(to: CommandLine.arguments[idx + 1])
            exit(0)
        }

        // Scriptable uninstall: restore sleep, remove the helper, delete settings.
        if CommandLine.arguments.contains("--uninstall") {
            controller.uninstall()
            print("Clawake uninstalled: sleep restored, lid-closed helper removed, settings deleted.")
            exit(0)
        }

        // Single instance only. A second copy would put a duplicate icon in the
        // menu bar and fight the first over the pmset/IOPMAssertion state, so if
        // another instance is already running, bring it forward and quit.
        let myPID = NSRunningApplication.current.processIdentifier
        let others = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "app.clawake.desktop")
            .filter { $0.processIdentifier != myPID }
        if !others.isEmpty {
            others.first?.activate(options: [])
            exit(0)
        }

        NSApp.setActivationPolicy(.accessory)  // menu-bar only, no dock

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = carIcon(active: false)
            btn.target = self
            btn.action = #selector(statusClicked)
        }

        popoverController = PopoverController(
            controller: controller, onOpenSetup: { [weak self] in self?.openSettings() })

        controller.onChange = { [weak self] in self?.refreshIcon() }
        controller.power.adoptDeepState()  // clean up any SleepDisabled left by a crash/force-quit
        controller.licensing.refresh()      // re-check the license (catches refunds/disables) in the background
        controller.tick()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.controller.tick()
        }

        refreshIcon()

        // First launch: open the menu bar panel (not the Settings window), the
        // way most menu bar apps introduce themselves. Deferred one runloop tick
        // so the status item is laid out first, otherwise the popover can open
        // detached from the menu bar with a gap.
        if !controller.didOnboard {
            controller.markOnboarded()
            DispatchQueue.main.async { [weak self] in
                guard let self, let button = self.statusItem.button else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.popoverController.show(from: button)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    @objc func statusClicked() {
        guard let button = statusItem.button else { return }
        popoverController.toggle(from: button)
    }

    func refreshIcon() {
        statusItem.button?.image = carIcon(active: controller.awake)
        statusItem.button?.toolTip = "Clawake: \(controller.statusTitle)"
    }

    func openSettings() {
        if settings == nil { settings = SettingsController(controller: controller) }
        settings?.show()
    }
}
