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

func appVersion() -> String {
    (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()
    var statusItem: NSStatusItem!
    var popoverController: PopoverController!
    var onboarding: OnboardingController?
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // menu-bar only, no dock

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = carIcon(active: false)
            btn.target = self
            btn.action = #selector(statusClicked)
        }

        popoverController = PopoverController(
            controller: controller, onOpenSetup: { [weak self] in self?.openOnboarding() })

        controller.onChange = { [weak self] in self?.refreshIcon() }
        controller.tick()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.controller.tick()
        }

        if !controller.setupComplete { openOnboarding() }
        refreshIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    @objc func statusClicked() {
        guard let button = statusItem.button else { return }
        if controller.setupComplete {
            popoverController.toggle(from: button)
        } else {
            openOnboarding()
        }
    }

    func refreshIcon() {
        statusItem.button?.image = carIcon(active: controller.awake)
        statusItem.button?.toolTip = "Clawake: \(controller.statusTitle)"
    }

    func openOnboarding() {
        if onboarding == nil { onboarding = OnboardingController(controller: controller) }
        onboarding?.show()
    }
}
