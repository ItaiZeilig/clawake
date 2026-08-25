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
            w.setContentSize(NSSize(width: 460, height: 520))
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
    @State private var hooked = false
    @State private var installing = false
    @State private var note1 = ""
    @State private var note2 = ""

    private let bg = Color(red: 0.09, green: 0.09, blue: 0.10)
    private let card = Color(red: 0.13, green: 0.13, blue: 0.15)
    private let orange = Color(red: 0.91, green: 0.52, blue: 0.29)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        if let img = carIcon(active: true) {
                            Image(nsImage: img).resizable().interpolation(.none)
                                .frame(width: 56, height: 56)
                        }
                        Text("Welcome to Clawake").font(.system(size: 22, weight: .bold))
                        Text("Finish setup to start keeping your Mac awake.")
                            .foregroundColor(.secondary)
                    }.padding(.top, 8)

                    cardBox(number: 1, done: setupDone, title: "Allow lid-closed keep-awake",
                            body: "Keeping your Mac awake with the lid closed requires a one-time macOS administrator approval. Clawake adds a small, scoped rule for this and never asks again.") {
                        VStack(alignment: .leading, spacing: 8) {
                            Button(action: enable) {
                                Text(setupDone ? "Enabled" : (installing ? "Waiting for password…" : "Enable"))
                            }
                            .tint(orange)
                            .disabled(setupDone || installing)
                            if !note1.isEmpty {
                                Text(note1).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }

                    cardBox(number: 2, done: hooked, title: "Connect Claude Code (optional)",
                            body: "Add Clawake's hooks to Claude Code so the Follow Claude sessions mode knows when Claude is working. One click, no restart.") {
                        VStack(alignment: .leading, spacing: 8) {
                            Button(action: connect) { Text(hooked ? "Connected" : "Connect") }
                                .disabled(hooked)
                            if !note2.isEmpty {
                                Text(note2).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }.padding(24)
            }
            Divider()
            HStack {
                Button(action: onClose) { Text("Close").foregroundColor(.secondary) }
                    .buttonStyle(.plain)
                Spacer()
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 460, height: 520)
        .background(bg)
        .onAppear(perform: refresh)
    }

    private func cardBox<Content: View>(
        number: Int, done: Bool, title: String, body: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 22, height: 22)
                Text(done ? "✓" : "\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(done ? .black : .white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(body).font(.system(size: 12)).foregroundColor(.secondary)
                content()
            }
            Spacer()
        }
        .padding(15)
        .background(card)
        .cornerRadius(12)
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

    private func connect() {
        let ok = controller.connectClaude()
        note2 = ok
            ? "Connected. New Claude Code sessions will keep your Mac awake."
            : "Could not update your Claude settings."
        refresh()
    }

    private func refresh() {
        setupDone = controller.setupComplete
        hooked = controller.hooksConnected
    }
}
