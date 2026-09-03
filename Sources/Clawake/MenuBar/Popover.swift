import AppKit
import SwiftUI
import ClawakeCore

enum PanelStyle {
    case material  // native frosted, adapts to light/dark
    case solid     // solid dark, branded
}

/// The main control: a native NSPopover with a designed SwiftUI panel.
final class PopoverController {
    let popover = NSPopover()

    init(controller: AppState, style: PanelStyle = .material, onOpenSetup: @escaping () -> Void) {
        popover.behavior = .transient  // click-away dismissal, like a system menu
        popover.animates = true
        if style == .solid { popover.appearance = NSAppearance(named: .darkAqua) }
        let view = PopoverView(
            controller: controller, style: style,
            onSetup: { onOpenSetup() }, onQuit: { NSApp.terminate(nil) })
        let hosting = NSHostingController(rootView: view)
        // Size the popover exactly to the SwiftUI content. Without this the
        // hosting controller can reserve extra space, which shows up as a gap
        // between the popover and the menu bar.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
    }

    func toggle(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show(from: button)
        }
    }

    /// Show the popover anchored to the status item (no-op if already shown).
    func show(from button: NSStatusBarButton) {
        guard !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

struct PopoverView: View {
    @ObservedObject var controller: AppState
    var style: PanelStyle = .material
    let onSetup: () -> Void
    let onQuit: () -> Void

    private let orange = Color(red: 0.91, green: 0.52, blue: 0.29)

    var body: some View {
        VStack(spacing: 0) {
            header
            controlCard
            if controller.lidNeedsInstall { installBanner }
            else if controller.lidApprovalNeeded { approvalBanner }
            infoSection
            Divider().opacity(style == .solid ? 0.25 : 1)
            footer
        }
        .frame(width: 300)
        .background(panelBackground)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 10) {
            if let img = carIcon(active: true) {
                Image(nsImage: img).resizable().interpolation(.none).frame(width: 24, height: 24)
            }
            Text("Clawake").font(.system(size: 14, weight: .semibold))
            Spacer()
            Text("v\(appVersion())").font(.system(size: 10)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    // MARK: the hero control (big label + prominent switch)

    private var controlCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(controller.isOn ? "On" : "Off")
                    .font(.system(size: 20, weight: .bold))
                HStack(spacing: 6) {
                    Circle().fill(dotColor).frame(width: 8, height: 8)
                    Text(controller.statusTitle).font(.system(size: 12)).foregroundColor(.secondary)
                }
                if !controller.statusDetail.isEmpty {
                    Text(controller.statusDetail)
                        .font(.system(size: 11)).foregroundColor(.secondary).opacity(0.75)
                        .padding(.leading, 14)
                }
                if !controller.timerRemaining.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "timer").font(.system(size: 10))
                        Text(controller.timerRemaining).font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(orange)
                }
            }
            Spacer()
            Button(action: { controller.setOn(!controller.isOn) }) {
                BrandSwitch(isOn: controller.isOn, onColor: orange)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(cardFill)
        )
        .padding(.horizontal, 12).padding(.bottom, 10)
    }

    // MARK: live info (power / temperature / lid)

    private var infoSection: some View {
        VStack(spacing: 8) {
            infoRow(
                symbol: controller.powerText.hasPrefix("Battery") ? "battery.100" : "powerplug",
                label: "Power", value: controller.powerText, tint: .secondary)
            infoRow(
                symbol: "thermometer.medium", label: "Temperature",
                value: controller.thermalText, tint: thermalColor)
            infoRow(
                symbol: controller.lidClosedOn ? "laptopcomputer" : "laptopcomputer.slash",
                label: "Lid closed",
                value: controller.lidClosedOn ? "On" : "Off",
                tint: .secondary)
        }
        .padding(.horizontal, 18).padding(.bottom, 12)
    }

    private func infoRow(symbol: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundColor(.secondary)
                .frame(width: 16)
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium)).foregroundColor(tint)
        }
    }

    private var thermalColor: Color {
        switch controller.thermalLevelRaw {
        case ThermalLevel.serious.rawValue: return orange
        case ThermalLevel.critical.rawValue: return .red
        case ThermalLevel.fair.rawValue: return .primary
        default: return .secondary
        }
    }

    private var approvalBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield").font(.system(size: 12)).foregroundColor(orange)
            Text("Approve lid-closed keep-awake")
                .font(.system(size: 11)).foregroundColor(.primary)
            Spacer()
            Button(action: { controller.approveLid { _ in } }) {
                Text("Approve")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(orange))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(orange.opacity(0.12)))
        .padding(.horizontal, 12).padding(.bottom, 10)
    }

    /// Shown when lid-closed is wanted but the app is not in a real install location.
    /// Registering the privileged helper from a DMG or download would poison the
    /// registration, so we ask the user to move the app to Applications first.
    private var installBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.app").font(.system(size: 12)).foregroundColor(orange)
            Text("Move Clawake to Applications for lid-closed")
                .font(.system(size: 11)).foregroundColor(.primary)
            Spacer()
            Button(action: {
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            }) {
                Text("Show")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(orange))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(orange.opacity(0.12)))
        .padding(.horizontal, 12).padding(.bottom, 10)
    }

    private var footer: some View {
        HStack {
            footerButton("Settings", symbol: "gearshape", action: onSetup)
            Spacer()
            footerButton("Quit", symbol: "power", action: onQuit)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: style bits

    @ViewBuilder private var panelBackground: some View {
        switch style {
        case .material: Rectangle().fill(.regularMaterial).ignoresSafeArea()
        case .solid: Color(red: 0.11, green: 0.11, blue: 0.12).ignoresSafeArea()
        }
    }

    private var cardFill: Color {
        style == .solid ? Color.white.opacity(0.06) : Color.primary.opacity(0.05)
    }

    private var dotColor: Color {
        if controller.awake { return .green }
        if controller.statusTitle.hasPrefix("Paused") { return orange }
        return Color.secondary.opacity(0.5)
    }

    private func footerButton(_ title: String, symbol: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(title).font(.system(size: 12))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
