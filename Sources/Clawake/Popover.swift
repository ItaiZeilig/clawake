import AppKit
import SwiftUI

/// The main control: a native NSPopover with a designed SwiftUI panel.
final class PopoverController {
    let popover = NSPopover()

    init(controller: Controller, onOpenSetup: @escaping () -> Void) {
        popover.behavior = .transient  // click-away dismissal, like a system menu
        popover.animates = true
        let view = PopoverView(
            controller: controller,
            onSetup: { onOpenSetup() },
            onQuit: { NSApp.terminate(nil) }
        )
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

/// Translucent native material behind the panel (the standard macOS popover look).
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct PopoverView: View {
    @ObservedObject var controller: Controller
    let onSetup: () -> Void
    let onQuit: () -> Void

    private let orange = Color(red: 0.91, green: 0.52, blue: 0.29)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, 12)
            mainRow
            powerRow
            Divider().padding(.horizontal, 12)
            footer
        }
        .frame(width: 300)
        .background(VisualEffectBackground().ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let img = carIcon(active: true) {
                Image(nsImage: img).resizable().interpolation(.none).frame(width: 26, height: 26)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Clawake").font(.system(size: 14, weight: .semibold))
                Text("Keeps your Mac awake").font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Text("v\(appVersion())").font(.system(size: 10)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
    }

    private var mainRow: some View {
        HStack(spacing: 12) {
            Circle().fill(dotColor).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.statusTitle).font(.system(size: 13, weight: .medium))
                Text(controller.statusDetail).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { controller.isOn }, set: { controller.setOn($0) }))
                .labelsHidden().toggleStyle(.switch).tint(orange)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private var powerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: controller.powerText.hasPrefix("Battery") ? "battery.100" : "powerplug")
                .font(.system(size: 10)).foregroundColor(.secondary)
            Text(controller.powerText).font(.system(size: 11)).foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    private var footer: some View {
        HStack {
            footerButton("Setup", symbol: "gearshape", action: onSetup)
            Spacer()
            footerButton("Quit", symbol: "power", action: onQuit)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
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
