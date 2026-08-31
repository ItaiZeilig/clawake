import AppKit
import SwiftUI

enum PanelStyle {
    case material  // native frosted, adapts to light/dark
    case solid     // solid dark, branded
}

/// A larger, brand-colored switch. Custom-drawn so it renders in previews and
/// reads as designed rather than a stock control.
struct BrandSwitch: View {
    let isOn: Bool
    let onColor: Color

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? onColor : Color.secondary.opacity(0.35))
            Circle()
                .fill(Color.white)
                .padding(3)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        }
        .frame(width: 50, height: 30)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

/// The main control: a native NSPopover with a designed SwiftUI panel.
final class PopoverController {
    let popover = NSPopover()

    init(controller: Controller, style: PanelStyle = .material, onOpenSetup: @escaping () -> Void) {
        popover.behavior = .transient  // click-away dismissal, like a system menu
        popover.animates = true
        if style == .solid { popover.appearance = NSAppearance(named: .darkAqua) }
        let view = PopoverView(
            controller: controller, style: style,
            onSetup: { onOpenSetup() }, onQuit: { NSApp.terminate(nil) })
        popover.contentViewController = NSHostingController(rootView: view)
    }

    func toggle(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

struct PopoverView: View {
    @ObservedObject var controller: Controller
    var style: PanelStyle = .material
    let onSetup: () -> Void
    let onQuit: () -> Void

    private let orange = Color(red: 0.91, green: 0.52, blue: 0.29)

    var body: some View {
        VStack(spacing: 0) {
            header
            controlCard
            powerRow
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

    private var powerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: controller.powerText.hasPrefix("Battery") ? "battery.100" : "powerplug")
                .font(.system(size: 10))
            Text(controller.powerText).font(.system(size: 11))
            Spacer()
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 18).padding(.bottom, 12)
    }

    private var footer: some View {
        HStack {
            footerButton("Setup", symbol: "gearshape", action: onSetup)
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
