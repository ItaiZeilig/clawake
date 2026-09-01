import Foundation
import Security
import ClawakeShared

/// The XPC listener delegate and exported object. Every connection is verified to
/// come from our own Developer-ID-signed app before the privileged interface is
/// exposed; accepted calls are forwarded to `SleepManager`. No other process can
/// drive the daemon.
final class HelperService: NSObject, NSXPCListenerDelegate, ClawakeHelperProtocol {
    private let sleep = SleepManager()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        guard Self.isValidClient(c) else { return false }
        c.exportedInterface = NSXPCInterface(with: ClawakeHelperProtocol.self)
        c.exportedObject = self
        c.resume()
        return true
    }

    // MARK: ClawakeHelperProtocol

    func setSleepDisabled(_ on: Bool, reply: @escaping (Bool) -> Void) {
        reply(sleep.setSleepDisabled(on))
    }

    func ping(reply: @escaping (Int) -> Void) { reply(HelperConstants.version) }

    // MARK: client verification

    /// True only if the connecting process is our app, signed by our Developer ID team.
    static func isValidClient(_ connection: NSXPCConnection) -> Bool {
        guard var token = auditToken(of: connection) else { return false }
        let tokenData = Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)

        var code: SecCode?
        let attrs = [kSecGuestAttributeAudit: tokenData] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess,
              let code else { return false }

        let requirement =
            "identifier \"\(HelperConstants.appBundleID)\" and anchor apple generic and "
            + "certificate leaf[subject.OU] = \"\(HelperConstants.teamID)\""
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess,
              let req else { return false }

        return SecCodeCheckValidity(code, [], req) == errSecSuccess
    }

    /// The connecting peer's audit token. NSXPCConnection carries it as a private
    /// `auditToken` property; read it via KVC as an NSValue wrapping audit_token_t.
    private static func auditToken(of connection: NSXPCConnection) -> audit_token_t? {
        guard let value = connection.value(forKey: "auditToken") as? NSValue else { return nil }
        var token = audit_token_t()
        withUnsafeMutableBytes(of: &token) { buf in
            value.getValue(buf.baseAddress!, size: MemoryLayout<audit_token_t>.size)
        }
        return token
    }
}
