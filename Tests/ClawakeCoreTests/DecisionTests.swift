import XCTest
@testable import ClawakeCore

final class DecisionTests: XCTestCase {

    private func input(
        mode: Mode = .on, onBattery: Bool = false, batteryPercent: Int? = nil,
        minPercent: Int = 15, onlyOnAC: Bool = false, thermalPaused: Bool = false,
        lidClosed: Bool = false
    ) -> DecideInput {
        DecideInput(
            mode: mode, onBattery: onBattery, batteryPercent: batteryPercent,
            minPercent: minPercent, onlyOnAC: onlyOnAC, thermalPaused: thermalPaused,
            lidClosed: lidClosed)
    }

    func testOffIsNeverAwake() {
        let d = decide(input(mode: .off, lidClosed: true))
        XCTAssertFalse(d.awake)
        XCTAssertFalse(d.deep)
        XCTAssertEqual(d.reason, "off")
    }

    func testAwakeOnACByDefault() {
        let d = decide(input())
        XCTAssertTrue(d.awake)
        XCTAssertFalse(d.deep)   // lid-closed off -> light layer only
        XCTAssertEqual(d.reason, "on")
    }

    func testLidClosedEngagesDeepWhenAwake() {
        let d = decide(input(lidClosed: true))
        XCTAssertTrue(d.awake)
        XCTAssertTrue(d.deep)
    }

    func testBatteryFloorPausesAtOrBelowThreshold() {
        XCTAssertFalse(decide(input(onBattery: true, batteryPercent: 15, minPercent: 15)).awake,
                       "at the threshold it should pause")
        XCTAssertFalse(decide(input(onBattery: true, batteryPercent: 10, minPercent: 15)).awake)
        XCTAssertEqual(decide(input(onBattery: true, batteryPercent: 10, minPercent: 15)).reason, "battery-low")
    }

    func testBatteryFloorStaysAwakeAboveThreshold() {
        XCTAssertTrue(decide(input(onBattery: true, batteryPercent: 40, minPercent: 15)).awake)
    }

    func testBatteryFloorIgnoredWhenDisabled() {
        // minPercent == 0 means "pause on low battery" is off.
        XCTAssertTrue(decide(input(onBattery: true, batteryPercent: 2, minPercent: 0)).awake)
    }

    func testBatteryFloorDoesNotApplyOnAC() {
        XCTAssertTrue(decide(input(onBattery: false, batteryPercent: 5, minPercent: 15)).awake)
    }

    func testOnlyOnACSleepsOnBattery() {
        let d = decide(input(onBattery: true, batteryPercent: 90, onlyOnAC: true))
        XCTAssertFalse(d.awake)
        XCTAssertEqual(d.reason, "battery-only-ac")
    }

    func testThermalPausePreemptsAwake() {
        let d = decide(input(thermalPaused: true, lidClosed: true))
        XCTAssertFalse(d.awake)
        XCTAssertFalse(d.deep)
        XCTAssertEqual(d.reason, "thermal")
    }

    // Priority: battery floor is checked before only-on-AC and thermal.
    func testBatteryLowWinsOverThermal() {
        let d = decide(input(onBattery: true, batteryPercent: 5, minPercent: 15, thermalPaused: true))
        XCTAssertEqual(d.reason, "battery-low")
    }
}

final class ThermalTests: XCTestCase {

    func testAtOrAboveCutoffSerious() {
        XCTAssertTrue(atOrAboveCutoff(.serious, .serious))
        XCTAssertTrue(atOrAboveCutoff(.critical, .serious))
        XCTAssertFalse(atOrAboveCutoff(.fair, .serious))
        XCTAssertFalse(atOrAboveCutoff(.unknown, .serious))
    }

    func testCriticalCutoffOnlyTripsOnCritical() {
        XCTAssertFalse(atOrAboveCutoff(.serious, .critical))
        XCTAssertTrue(atOrAboveCutoff(.critical, .critical))
    }

    func testHysteresisLatchesUntilNominal() {
        // Not paused, warms to serious -> paused.
        XCTAssertTrue(nextThermalPaused(false, .serious, .serious))
        // Already paused, cools to fair (not nominal) -> stays paused.
        XCTAssertTrue(nextThermalPaused(true, .fair, .serious))
        // Already paused, reaches nominal -> releases.
        XCTAssertFalse(nextThermalPaused(true, .nominal, .serious))
        // Not paused, only fair -> stays running.
        XCTAssertFalse(nextThermalPaused(false, .fair, .serious))
    }
}

final class BatteryParsingTests: XCTestCase {

    func testParsesBatteryPercentAndSource() {
        let out = "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=123)\t45%; discharging; 2:30 remaining present: true"
        let r = parsePmsetBatt(out)
        XCTAssertTrue(r.onBattery)
        XCTAssertEqual(r.percent, 45)
    }

    func testParsesACPower() {
        let out = "Now drawing from 'AC Power'\n -InternalBattery-0 (id=123)\t99%; charging; 0:08 remaining present: true"
        let r = parsePmsetBatt(out)
        XCTAssertFalse(r.onBattery)
        XCTAssertEqual(r.percent, 99)
    }

    func testClampsToHundred() {
        XCTAssertEqual(parsePmsetBatt("'AC Power' 250%").percent, 100)
    }
}
