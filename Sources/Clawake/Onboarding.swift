import AppKit
import SwiftUI

final class OnboardingController {
    private var window: NSWindow?
    private let controller: Controller

    init(controller: Controller) { self.controller = controller }

    func show() {
        if window == nil {
            let root = OnboardingView(controller: controller, onClose: { [weak self] in self?.close() })
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "Clawake Setup"
            w.styleMask = [.titled, .closable]
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true  // adapts to light/dark; blends with content
            w.setContentSize(NSSize(width: 460, height: 400))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)  // let the window come forward
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }
}

struct OnboardingView: View {
    let controller: Controller
    let onClose: () -> Void

    @State private var setupDone = false
    @State private var installing = false
    @State private var note1 = ""

    private let orange = Color(red: 0.91, green: 0.52, blue: 0.29)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    if let img = carIcon(active: true) {
                        Image(nsImage: img).resizable().interpolation(.none)
                            .frame(width: 56, height: 56)
                    }
                    Text("Welcome to Clawake").font(.system(size: 22, weight: .bold))
                    Text("Finish setup to start keeping your Mac awake.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }.padding(.top, 6)

                cardBox(number: 1, done: setupDone, title: "Allow lid-closed keep-awake",
                        body: "Keeping your Mac awake with the lid closed needs a one-time macOS administrator approval. Clawake adds a small, scoped rule for this and never asks again.") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: enable) {
                            Text(setupDone ? "Enabled" : (installing ? "Waiting for password…" : "Enable"))
                                .frame(minWidth: 64)
                        }
                        .tint(orange)
                        .controlSize(.large)
                        .disabled(setupDone || installing)
                        if !note1.isEmpty {
                            Text(note1).font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                }
            }.padding(24)
            Spacer(minLength: 0)
            Divider()
            HStack {
                Button(action: onClose) { Text("Close").foregroundColor(.secondary) }
                    .buttonStyle(.plain)
                Spacer()
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 460, height: 400)
        .onAppear(perform: refresh)
    }

    private func cardBox<Content: View>(
        number: Int, done: Bool, title: String, body: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.secondary.opacity(0.25))
                    .frame(width: 22, height: 22)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(number)").font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(body).font(.system(size: 12)).foregroundColor(.secondary)
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }

    private func enable() {
        installing = true
        note1 = "A macOS password prompt will appear."
        DispatchQueue.global().async {
            let ok = controller.installLidHelper()
            DispatchQueue.main.async {
                installing = false
                note1 = ok
                    ? "Done. Lid-closed keep-awake is ready."
                    : "That did not go through. Please try again."
                refresh()
            }
        }
    }

    private func refresh() {
        setupDone = controller.setupComplete
    }
}
