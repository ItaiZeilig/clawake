import Foundation
import Combine
import ClawakeCore

/// Store-specific constants. Fill in your Lemon Squeezy checkout link.
enum LicenseConfig {
    /// The Lemon Squeezy hosted-checkout (Buy) URL for the $5 Clawake license.
    /// TODO: replace with your real product checkout URL from the LS dashboard.
    static let checkoutURL = URL(string: "https://clawake.lemonsqueezy.com/buy/REPLACE-WITH-PRODUCT-ID")!
    /// Where buyers find their key if they lose the email.
    static let manageURL = URL(string: "https://app.lemonsqueezy.com/my-orders")!
}

/// Owns the trial + license lifecycle: loads/saves the record in the Keychain,
/// derives the `LicenseState` (via the pure `evaluateLicense`), and talks to Lemon
/// Squeezy to activate / validate / deactivate. Published so the UI can react.
final class Licensing: ObservableObject {
    @Published private(set) var state: LicenseState = .expired
    @Published private(set) var busy = false
    @Published private(set) var lastError: String?

    private var record: LicenseRecord
    private static let account = "record"

    init() {
        // The render/preview tool runs as an unsigned binary; touching the Keychain
        // there pops a blocking "wants to access your keychain" prompt. Use an
        // ephemeral in-memory trial instead so previews never hit the Keychain.
        if Licensing.isPreview {
            record = LicenseRecord(trialStart: Date())
            state = evaluateLicense(record)
            return
        }
        record = Licensing.load() ?? LicenseRecord()
        // First ever launch: start the trial clock.
        if record.licenseKey == nil, record.trialStart == nil {
            record.trialStart = Date()
            Licensing.save(record)
        }
        state = evaluateLicense(record)
    }

    private static var isPreview: Bool {
        let args = CommandLine.arguments
        return args.contains("--render-panel") || args.contains("--render-settings")
    }

    var isActive: Bool { state.isActive }
    var isLicensed: Bool { state == .licensed }
    var trialDaysLeft: Int? { if case .trial(let d) = state { return d } else { return nil } }

    /// Re-derive state and, if licensed, re-validate in the background to catch a
    /// refund/disable. Network failure leaves the current state untouched (offline
    /// friendly). Call on launch.
    func refresh() {
        state = evaluateLicense(record)
        guard let key = record.licenseKey, let inst = record.instanceId else { return }
        LemonSqueezy.validate(key: key, instanceId: inst) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if case .success(let valid) = result {
                    self.record.lastValidated = Date()
                    self.record.lastValidResult = valid
                    Licensing.save(self.record)
                    self.state = evaluateLicense(self.record)
                }
            }
        }
    }

    /// Activate a pasted license key against this Mac.
    func activate(key rawKey: String, completion: ((Bool) -> Void)? = nil) {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { lastError = "Enter your license key."; completion?(false); return }
        busy = true
        lastError = nil
        LemonSqueezy.activate(key: key, instanceName: MachineID.current()) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                switch result {
                case .success(let instanceId):
                    self.record.licenseKey = key
                    self.record.instanceId = instanceId
                    self.record.lastValidated = Date()
                    self.record.lastValidResult = true
                    Licensing.save(self.record)
                    self.state = evaluateLicense(self.record)
                    completion?(true)
                case .failure(let e):
                    self.lastError = e.localizedDescription
                    completion?(false)
                }
            }
        }
    }

    /// Release this machine's activation so the license can move to another Mac.
    func deactivate(completion: ((Bool) -> Void)? = nil) {
        guard let key = record.licenseKey, let inst = record.instanceId else { completion?(false); return }
        busy = true
        LemonSqueezy.deactivate(key: key, instanceId: inst) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.record.licenseKey = nil
                self.record.instanceId = nil
                self.record.lastValidResult = false
                Licensing.save(self.record)
                self.state = evaluateLicense(self.record)
                completion?(true)
            }
        }
    }

    // MARK: Keychain persistence

    private static func load() -> LicenseRecord? {
        guard let data = Keychain.get(account: account) else { return nil }
        return try? JSONDecoder().decode(LicenseRecord.self, from: data)
    }

    private static func save(_ r: LicenseRecord) {
        if let data = try? JSONEncoder().encode(r) { Keychain.set(data, account: account) }
    }
}
