import AppKit
import SwiftUI

/// The Settings window. On first launch it also serves as the welcome screen;
/// afterwards it opens from the panel's "Settings" button.
final class SettingsController {
    private var window: NSWindow?
    private let controller: Controller

    init(controller: Controller) { self.controller = controller }

    func show() {
        if window == nil {
            let root = SettingsView(controller: controller, onClose: { [weak self] in self?.close() })
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "Clawake"
            w.styleMask = [.titled, .closable]
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true  // adapts to light/dark; blends with content
            w.setContentSize(NSSize(width: 440, height: 600))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)  // let the window come forward
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        controller.markOnboarded()
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsView: View {
    @ObservedObject var controller: Controller
    let onClose: () -> Void
    var scroll = true  // ImageRenderer draws ScrollView content blank; off for render checks

    private let orange = Color(red: 0.91, green: 0.52, blue: 0.29)
    private let batteryOptions = [10, 15, 20, 30]

    @ViewBuilder private var rows: some View {
        VStack(spacing: 14) {
            header
            lidRow
            batteryRow
            acRow
            thermalRow
        }
        .padding(20)
    }

    var body: some View {
        VStack(spacing: 0) {
            if scroll {
                ScrollView { rows }
            } else {
                rows
            }
            Divider()
            HStack {
                Button(action: onClose) { Text("Done").foregroundColor(.secondary) }
                    .buttonStyle(.plain)
                Spacer()
                Text("v\(appVersion())").font(.system(size: 11)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 440, height: 600)
        .onAppear { controller.tick() }
    }

    // MARK: header

    private var header: some View {
        VStack(spacing: 8) {
            if let img = carIcon(active: true) {
                Image(nsImage: img).resizable().interpolation(.none).frame(width: 52, height: 52)
            }
            Text(controller.didOnboard ? "Settings" : "Welcome to Clawake")
                .font(.system(size: 20, weight: .bold))
            Text("Choose how Clawake keeps your Mac awake.")
                .font(.system(size: 12)).foregroundColor(.secondary)
        }
        .padding(.top, 4).padding(.bottom, 4)
    }

    // MARK: rows

    private var lidRow: some View {
        settingRow(
            icon: "macbook", title: "Keep awake with the lid closed",
            subtitle: lidSubtitle,
            isOn: controller.lidClosedOn, onToggle: toggleLid
        )
    }

    private var lidSubtitle: String {
        if controller.lidClosedOn {
            return controller.lidApprovalNeeded
                ? "Needs a one-time macOS approval."
                : "Your Mac stays awake even when you shut the lid."
        }
        return "Your Mac will sleep when you close the lid."
    }

    private var batteryRow: some View {
        settingRow(
            icon: "battery.25", title: "Pause on low battery",
            subtitle: "Let your Mac sleep when the battery runs low.",
            isOn: controller.pauseOnLowBattery, onToggle: controller.setPauseOnLowBattery
        ) {
            if controller.pauseOnLowBattery {
                HStack(spacing: 8) {
                    Text("Below").font(.system(size: 12)).foregroundColor(.secondary)
                    SegmentedPills(
                        options: batteryOptions.map { "\($0)%" },
                        selected: batteryOptions.firstIndex(of: controller.batteryThreshold) ?? 1,
                        onSelect: { controller.setBatteryThreshold(batteryOptions[$0]) },
                        tint: orange)
                }
                .padding(.top, 4)
            }
        }
    }

    private var acRow: some View {
        settingRow(
            icon: "powerplug", title: "Only when plugged in",
            subtitle: "Keep awake on AC power; sleep on battery.",
            isOn: controller.onlyOnAC, onToggle: controller.setOnlyOnAC
        )
    }

    private var thermalRow: some View {
        settingRow(
            icon: "thermometer.medium", title: "Cool-down protection",
            subtitle: "Pause keeping awake if your Mac gets too hot.",
            isOn: controller.thermalProtect, onToggle: controller.setThermalProtect
        ) {
            if controller.thermalProtect {
                HStack(spacing: 8) {
                    Text("Pause when").font(.system(size: 12)).foregroundColor(.secondary)
                    SegmentedPills(
                        options: ["Hot", "Very hot"],
                        selected: controller.thermalCritical ? 1 : 0,
                        onSelect: { controller.setThermalCritical($0 == 1) },
                        tint: orange)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: row builder

    private func settingRow(
        icon: String, title: String, subtitle: String,
        isOn: Bool, onToggle: @escaping (Bool) -> Void,
        @ViewBuilder extra: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.system(size: 16))
                    .foregroundColor(isOn ? orange : .secondary)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: { onToggle(!isOn) }) {
                    BrandSwitch(isOn: isOn, onColor: orange, size: 0.85)
                }
                .buttonStyle(.plain)
            }
            extra().padding(.leading, 34)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }

    // MARK: actions

    private func toggleLid(_ on: Bool) {
        controller.setLidClosedWanted(on)
        if on && !controller.helperReady() {
            controller.approveLid { _ in }
        }
    }
}
