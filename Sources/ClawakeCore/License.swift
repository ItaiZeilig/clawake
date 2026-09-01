import Foundation

// MARK: - Licensing (pure state logic; IO lives in the app target)

/// Everything we persist about the trial and any activated license. Stored in the
/// Keychain by the app so it survives trashing/reinstalling the app.
public struct LicenseRecord: Codable, Equatable {
    public var trialStart: Date?      // set once, on first ever launch
    public var licenseKey: String?    // the Lemon Squeezy key, once activated
    public var instanceId: String?    // the activation instance id LS returned
    public var lastValidated: Date?   // when we last called /validate (informational)
    public var lastValidResult: Bool  // the result of that last validation

    public init(
        trialStart: Date? = nil, licenseKey: String? = nil, instanceId: String? = nil,
        lastValidated: Date? = nil, lastValidResult: Bool = false
    ) {
        self.trialStart = trialStart
        self.licenseKey = licenseKey
        self.instanceId = instanceId
        self.lastValidated = lastValidated
        self.lastValidResult = lastValidResult
    }
}

public enum LicenseState: Equatable {
    case trial(daysLeft: Int)
    case licensed
    case expired
}

public enum LicensePolicy {
    public static let trialDays = 30
}

/// Decide the current license state from the stored record. Pure and testable.
///
/// A record counts as licensed as soon as it has an activated key whose last
/// validation succeeded. We deliberately do NOT expire a paid license just because
/// we could not reach the server recently (that would lock a paying user out
/// offline); only a validation that explicitly comes back invalid (a refund or a
/// manual disable) clears `lastValidResult`. Until then the trial countdown governs.
public func evaluateLicense(_ r: LicenseRecord, now: Date = Date()) -> LicenseState {
    if r.licenseKey != nil, r.instanceId != nil, r.lastValidResult {
        return .licensed
    }
    if let start = r.trialStart {
        let daysUsed = Int(now.timeIntervalSince(start) / 86_400)
        let left = LicensePolicy.trialDays - daysUsed
        return left > 0 ? .trial(daysLeft: left) : .expired
    }
    return .expired
}

public extension LicenseState {
    /// Whether Clawake is allowed to keep the Mac awake at all.
    var isActive: Bool { self != .expired }
}
