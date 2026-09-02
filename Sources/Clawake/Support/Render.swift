import AppKit
import SwiftUI
import ClawakeCore

/// Renders the real `PopoverView` (the exact SwiftUI the live app draws) to a PNG.
/// Used only for marketing/preview shots via `Clawake --render-panel <out.png>`.
/// Not part of normal app launch.
func renderPanel(to path: String) {
    MainActor.assumeIsolated {
        let controller = AppState()
        // A clean, representative "on" state. This is the same view the app shows;
        // we only choose which values it displays for the shot.
        controller.fillForRender(
            isOn: true, awake: true, statusTitle: "Keeping your Mac awake",
            powerText: "Battery 84%", thermalText: "Normal",
            thermalLevel: .nominal, lidClosedOn: true,
            statusDetail: "Your session keeps running, lid closed")

        // The .solid style is a dark panel; the live app forces darkAqua so the
        // semantic text colors resolve light. ImageRenderer defaults to light, so
        // force the dark color scheme to match what users actually see.
        let view = PopoverView(
            controller: controller, style: .solid, onSetup: {}, onQuit: {})
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3  // retina crispness

        guard let cg = renderer.cgImage else {
            FileHandle.standardError.write(Data("render: no image produced\n".utf8))
            exit(1)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("render: png encode failed\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) (\(cg.width)x\(cg.height))")
        } catch {
            FileHandle.standardError.write(Data("render: write failed: \(error)\n".utf8))
            exit(1)
        }
    }
}

/// Renders the real Settings view to a PNG (light appearance), for previewing.
func renderSettings(to path: String) {
    MainActor.assumeIsolated {
        let controller = AppState()
        let view = SettingsView(controller: controller, onClose: {})
            .background(Color(red: 0.96, green: 0.96, blue: 0.97))
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        guard let cg = renderer.cgImage else {
            FileHandle.standardError.write(Data("render: no image produced\n".utf8)); exit(1)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("render: png encode failed\n".utf8)); exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(cg.width)x\(cg.height))")
    }
}
