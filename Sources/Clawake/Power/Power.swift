import Foundation
import IOKit.pwr_mgt
import ClawakeCore

/// Two layers:
///  - light: IOPMAssertion (prevent idle system sleep). No root.
///  - deep:  `pmset -a disablesleep` (survive a closed lid). Needs root; runs
///           through the SMAppService privileged daemon over XPC. Single-flight
///           + cooldown so a failure does not retry every tick.
final class PowerController {
    let helper = HelperClient()
    private var lightAssertion: IOPMAssertionID = 0
    private var lightActive = false
    private var displayAssertion: IOPMAssertionID = 0
    private var displayActive = false
    private(set) var deepEngaged = false
    private var deepBusy = false
    private var deepCooldownUntil = Date.distantPast

    func apply(_ decision: Decision) {
        // Light layer follows `awake`.
        if decision.awake && !lightActive {
            var id: IOPMAssertionID = 0
            let r = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Clawake keeping your Mac awake" as CFString,
                &id
            )
            if r == kIOReturnSuccess {
                lightAssertion = id
                lightActive = true
            }
        } else if !decision.awake && lightActive {
            IOPMAssertionRelease(lightAssertion)
            lightActive = false
        }

        // Deep layer follows `deep`, at most one pmset op in flight. We track
        // `deepEngaged` as true only after a confirmed enable, and clear it only
        // after a confirmed disable, so a failed daemon call retries on the next
        // tick instead of leaving `SleepDisabled 1` stuck on. That leftover is a
        // global system override: it would keep the Mac awake even when a guard
        // (low battery, only-on-AC, thermal) has decided it should sleep.
        let wantDeep = decision.awake && decision.deep
        if !deepBusy {
            if wantDeep && !deepEngaged && Date() >= deepCooldownUntil {
                deepBusy = true
                let ok = setDeep(true)
                deepEngaged = ok
                deepCooldownUntil = ok ? .distantPast : Date().addingTimeInterval(5 * 60)
                deepBusy = false
            } else if !wantDeep && deepEngaged && Date() >= deepCooldownUntil {
                deepBusy = true
                if setDeep(false) {
                    deepEngaged = false
                    deepCooldownUntil = .distantPast
                } else {
                    // Could not clear it right now; retry soon rather than every
                    // tick, and keep `deepEngaged` true so we know it is still set.
                    deepCooldownUntil = Date().addingTimeInterval(30)
                }
                deepBusy = false
            }
        }
    }

    /// Keep the display on, and therefore the screen unlocked. No root needed.
    /// This is the "don't lock" capability; when off, the display sleeps and the
    /// screen locks on the system's normal schedule.
    func setKeepDisplayOn(_ on: Bool) {
        if on && !displayActive {
            var id: IOPMAssertionID = 0
            let r = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Clawake keeping the screen unlocked" as CFString,
                &id)
            if r == kIOReturnSuccess { displayAssertion = id; displayActive = true }
        } else if !on && displayActive {
            IOPMAssertionRelease(displayAssertion)
            displayActive = false
        }
    }

    func releaseAll() {
        if lightActive {
            IOPMAssertionRelease(lightAssertion)
            lightActive = false
        }
        if displayActive {
            IOPMAssertionRelease(displayAssertion)
            displayActive = false
        }
        if deepEngaged {
            _ = setDeep(false)
            deepEngaged = false
        }
    }

    /// Reconcile the tracked deep state with what is actually set on the system.
    /// A previous run that was force-quit or crashed while lid-closed was engaged
    /// leaves `SleepDisabled 1` behind; adopting it here lets `apply()` clear it on
    /// this launch when it is no longer wanted (or keep it when it still is), so the
    /// Mac is never left permanently unable to sleep.
    func adoptDeepState() {
        let r = runProcess("/usr/bin/pmset", ["-g"])
        guard r.ok else { return }
        if let line = r.stdout.split(separator: "\n").first(where: { $0.contains("SleepDisabled") }) {
            deepEngaged = line.trimmingCharacters(in: .whitespaces).hasSuffix("1")
        }
    }

    /// Deep sleep-prevention runs through the privileged daemon over XPC.
    private func setDeep(_ on: Bool) -> Bool {
        helper.setSleepDisabled(on)
    }

    /// Whether the privileged daemon is registered and approved.
    func helperEnabled() -> Bool { helper.isEnabled }
}
