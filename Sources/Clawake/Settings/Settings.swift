import AppKit
import SwiftUI

/// The Settings window. On first launch it also serves as the welcome screen;
/// afterwards it opens from the panel's "Settings" button.
final class SettingsController {
    private var window: NSWindow?
    private let controller: AppState

    init(controller: AppState) { self.controller = controller }

    func show() {
        if window == nil {
            let root = SettingsView(controller: controller, onClose: { [weak self] in self?.close() })
            let hosting = NSHostingController(rootView: root)
            // Let the window size itself to the content's ideal height (and re-fit
            // when a section expands/collapses), instead of a guessed fixed height.
            hosting.sizingOptions = [.preferredContentSize]
            let w = NSWindow(contentViewController: hosting)
            w.title = "Clawake"
            w.styleMask = [.titled, .closable]  // no .resizable: fixed to content
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true  // adapts to light/dark; blends with content
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        // Stay an accessory app (no Dock icon). An accessory app can still show
        // and focus a window without switching to .regular.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func close() {
        controller.markOnboarded()
        window?.orderOut(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var controller: AppState
    let onClose: () -> Void

    private let orange = Color(red: 0.91, green: 0.52, blue: 0.29)
    private let batteryOptions = [10, 15, 20, 30]

    @ViewBuilder private var rows: some View {
        VStack(spacing: 14) {
            header
            timerRow
            lidRow
            if !controller.isEnterprise { lockRow }
            batteryRow
            acRow
            thermalRow
        }
        .padding(20)
    }

    var body: some View {
        VStack(spacing: 0) {
            rows
            Divider()
            HStack {
                Text("v\(appVersion())").font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Button(action: onClose) {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(orange))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 440)  // fixed width, height fits the content
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
            Text("Keep your Mac awake, even with the lid closed.")
                .font(.system(size: 12)).foregroundColor(.secondary)
        }
        .padding(.top, 4).padding(.bottom, 4)
    }

    // MARK: rows

    private var timerRow: some View {
        let running = !controller.timerRemaining.isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "timer").font(.system(size: 16))
                    .foregroundColor(running ? orange : .secondary)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Auto-off timer").font(.system(size: 14, weight: .semibold))
                    Text(running
                        ? controller.timerRemaining
                        : "Keep awake for a set time, then turn off by itself.")
                        .font(.system(size: 12))
                        .foregroundColor(running ? orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            WrapPills(
                options: ["Unlimited", "5m", "10m", "15m", "30m", "1h", "2h", "5h"],
                selected: controller.timerSelectionIndex,
                onSelect: { controller.setTimer(index: $0) },
                tint: orange)
                .padding(.leading, 34)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }

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

    private var lockRow: some View {
        settingRow(
            icon: controller.preventLockOn ? "lock.open" : "lock",
            title: "Don't lock the screen",
            subtitle: controller.preventLockOn
                ? "The screen stays on and never locks while Clawake is on."
                : "The screen turns off and locks on your normal schedule.",
            isOn: controller.preventLockOn, onToggle: controller.setPreventLock
        )
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
