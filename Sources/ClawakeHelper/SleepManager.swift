import Foundation

/// The one privileged operation the daemon performs: toggle the system-wide
/// `SleepDisabled` setting via `pmset -a disablesleep`. Isolated here so the
/// XPC and code-signature logic in `HelperService` stays separate from the code
/// that actually runs as root.
final class SleepManager {
    /// Set `pmset -a disablesleep` on/off. Returns true on success.
    @discardableResult
    func setSleepDisabled(_ on: Bool) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-a", "disablesleep", on ? "1" : "0"]
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }
}
