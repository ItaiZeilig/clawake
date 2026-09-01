import Foundation
import ServiceManagement
import ClawakeShared

/// App side of the privileged helper: registers/unregisters the SMAppService
/// daemon and sends it XPC messages. Replaces the old sudoers approach.
final class HelperClient {
    private var connection: NSXPCConnection?

    private var service: SMAppService { SMAppService.daemon(plistName: HelperConstants.plistName) }

    /// Current registration status (.enabled, .requiresApproval, .notRegistered, .notFound).
    var status: SMAppService.Status { service.status }
    var isEnabled: Bool { service.status == .enabled }

    /// Register the daemon. Depending on macOS this either prompts for admin
    /// approval or leaves the status at `.requiresApproval` until the user enables
    /// it in Login Items. Returns the status after the attempt.
    @discardableResult
    func register() -> SMAppService.Status {
        do { try service.register() }
        catch { NSLog("Clawake: helper register error: \(error.localizedDescription)") }
        return service.status
    }

    @discardableResult
    func unregister() -> Bool {
        do { try service.unregister(); return true }
        catch { NSLog("Clawake: helper unregister error: \(error.localizedDescription)"); return false }
    }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }

    // MARK: XPC

    private func proxy(_ onError: @escaping (Error) -> Void = { _ in }) -> ClawakeHelperProtocol? {
        if connection == nil {
            let c = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
            c.remoteObjectInterface = NSXPCInterface(with: ClawakeHelperProtocol.self)
            c.invalidationHandler = { [weak self] in self?.connection = nil }
            c.interruptionHandler = { [weak self] in self?.connection = nil }
            c.resume()
            connection = c
        }
        return connection?.remoteObjectProxyWithErrorHandler(onError) as? ClawakeHelperProtocol
    }

    /// Toggle deep sleep-prevention through the daemon. Blocks briefly for the reply
    /// (the reply arrives on a background queue, so this is safe to call from main).
    func setSleepDisabled(_ on: Bool, timeout: TimeInterval = 3) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        var result = false
        guard let p = proxy({ _ in sem.signal() }) else { return false }
        p.setSleepDisabled(on) { ok in result = ok; sem.signal() }
        _ = sem.wait(timeout: .now() + timeout)
        return result
    }

    /// Returns the helper's version if it answers, else nil.
    func ping(timeout: TimeInterval = 2) -> Int? {
        let sem = DispatchSemaphore(value: 0)
        var version: Int?
        guard let p = proxy({ _ in sem.signal() }) else { return nil }
        p.ping { v in version = v; sem.signal() }
        _ = sem.wait(timeout: .now() + timeout)
        return version
    }
}
