import XCTest
@testable import ClawakeCore

final class LicenseTests: XCTestCase {

    private func daysAgo(_ n: Double) -> Date { Date().addingTimeInterval(-n * 86_400) }

    func testFreshTrialHasFullDaysLeft() {
        let r = LicenseRecord(trialStart: Date())
        XCTAssertEqual(evaluateLicense(r), .trial(daysLeft: 30))
        XCTAssertTrue(evaluateLicense(r).isActive)
    }

    func testTrialCountsDown() {
        XCTAssertEqual(evaluateLicense(LicenseRecord(trialStart: daysAgo(10))), .trial(daysLeft: 20))
        XCTAssertEqual(evaluateLicense(LicenseRecord(trialStart: daysAgo(29))), .trial(daysLeft: 1))
    }

    func testTrialExpiresAtThirtyDays() {
        XCTAssertEqual(evaluateLicense(LicenseRecord(trialStart: daysAgo(30))), .expired)
        XCTAssertEqual(evaluateLicense(LicenseRecord(trialStart: daysAgo(45))), .expired)
        XCTAssertFalse(evaluateLicense(LicenseRecord(trialStart: daysAgo(45))).isActive)
    }

    func testActivatedLicenseIsLicensed() {
        let r = LicenseRecord(
            trialStart: daysAgo(100), licenseKey: "KEY", instanceId: "INST",
            lastValidated: Date(), lastValidResult: true)
        XCTAssertEqual(evaluateLicense(r), .licensed)
        XCTAssertTrue(evaluateLicense(r).isActive)
    }

    func testLicenseOutlivesAnExpiredTrial() {
        // Even with the trial long gone, a valid license keeps it active.
        let r = LicenseRecord(
            trialStart: daysAgo(365), licenseKey: "KEY", instanceId: "INST",
            lastValidResult: true)
        XCTAssertEqual(evaluateLicense(r), .licensed)
    }

    func testInvalidatedLicenseFallsBackToTrialThenExpired() {
        // A refunded/disabled key (lastValidResult == false) is not licensed.
        let stillInTrial = LicenseRecord(
            trialStart: daysAgo(5), licenseKey: "KEY", instanceId: "INST",
            lastValidResult: false)
        XCTAssertEqual(evaluateLicense(stillInTrial), .trial(daysLeft: 25))

        let trialOver = LicenseRecord(
            trialStart: daysAgo(40), licenseKey: "KEY", instanceId: "INST",
            lastValidResult: false)
        XCTAssertEqual(evaluateLicense(trialOver), .expired)
    }

    func testNoTrialAndNoLicenseIsExpired() {
        XCTAssertEqual(evaluateLicense(LicenseRecord()), .expired)
    }

    func testKeyWithoutInstanceIsNotLicensed() {
        // A key that was never activated (no instance id) does not count.
        let r = LicenseRecord(trialStart: daysAgo(40), licenseKey: "KEY", lastValidResult: true)
        XCTAssertEqual(evaluateLicense(r), .expired)
    }
}
