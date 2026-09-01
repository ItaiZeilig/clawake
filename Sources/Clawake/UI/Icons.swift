import AppKit

/// The menu-bar car icon (active/idle variants), loaded from the app bundle.
func carIcon(active: Bool) -> NSImage? {
    let name = active ? "car-active" : "car-idle"
    if let url = Bundle.main.url(forResource: name, withExtension: "png"),
       let img = NSImage(contentsOf: url) {
        img.size = NSSize(width: 20, height: 20)
        return img
    }
    return nil
}

/// The app's short version string (CFBundleShortVersionString), shown in the UI.
func appVersion() -> String {
    (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
}
