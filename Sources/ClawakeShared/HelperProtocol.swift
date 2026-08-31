import Foundation

/// Names and identities shared between the app and the privileged helper daemon.
public enum HelperConstants {
    /// launchd label / Mach service name for the daemon. Must match the plist Label.
    public static let machServiceName = "app.clawake.helper"
    /// The LaunchDaemon plist file embedded in the app bundle.
    public static let plistName = "app.clawake.helper.plist"
    /// The signing identity the two sides require of each other (Developer ID team).
    public static let teamID = "UXXB9YTYKF"
    /// The app's bundle identifier (the daemon only accepts calls from this app).
    public static let appBundleID = "app.clawake.desktop"
    /// The helper's own bundle-ish identifier (used in its designated requirement).
    public static let helperIdentifier = "app.clawake.helper"
    /// Current helper build version, so the app can tell if an update needs a re-register.
    public static let version = 1
}

/// The XPC interface the daemon exposes to the app. Root-privileged; keep it as
/// narrow as possible (only what the lid-closed feature needs).
@objc public protocol ClawakeHelperProtocol {
    /// Enable or disable `pmset -a disablesleep`. Replies true on success.
    func setSleepDisabled(_ on: Bool, reply: @escaping (Bool) -> Void)
    /// Liveness/version check. Replies with the helper's version number.
    func ping(reply: @escaping (Int) -> Void)
}
