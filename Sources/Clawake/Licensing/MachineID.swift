import Foundation
import IOKit
import CryptoKit

/// A stable, anonymous identifier for this Mac: the SHA-256 of the hardware
/// `IOPlatformUUID`. Used as the Lemon Squeezy activation instance name so a
/// license activates against the machine, not a guessable label. Hashed so we
/// never send the raw hardware id anywhere.
enum MachineID {
    static func current() -> String {
        let raw = platformUUID() ?? "clawake-unknown-machine"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let cf = IORegistryEntryCreateCFProperty(
            service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return nil }
        return cf as? String
    }
}
