import Foundation
import IOKit.pwr_mgt

/// Two layers, mirroring the Electron version:
///  - light: IOPMAssertion (prevent idle system sleep). No root.
///  - deep:  `pmset -a disablesleep` (survive a closed lid). Needs root; uses the
///           password-free sudoers helper, else one admin prompt. Single-flight
///           + cooldown so a decline does not re-prompt every tick.
final class PowerController {
    private var lightAssertion: IOPMAssertionID = 0
    private var lightActive = false
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

        // Deep layer follows `deep`, at most one pmset op in flight.
        let wantDeep = decision.awake && decision.deep
        if !deepBusy {
            if wantDeep && !deepEngaged && Date() >= deepCooldownUntil {
                deepBusy = true
                let ok = setDeep(true)
                deepEngaged = ok
                if !ok { deepCooldownUntil = Date().addingTimeInterval(5 * 60) }
                deepBusy = false
            } else if !wantDeep && deepEngaged {
                deepBusy = true
                _ = setDeep(false)
                deepEngaged = false
                deepBusy = false
            }
        }
    }

    func releaseAll() {
        if lightActive {
            IOPMAssertionRelease(lightAssertion)
            lightActive = false
        }
        if deepEngaged {
            _ = setDeep(false)
            deepEngaged = false
        }
    }

    private func setDeep(_ on: Bool) -> Bool {
        let arg = on ? "1" : "0"
        // Password-free path: pmset directly (matches the sudoers NOPASSWD rule).
        let viaSudo = runProcess("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", arg])
        if viaSudo.ok { return true }
        // Fallback: one native admin prompt.
        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(arg)\" with administrator privileges"
        return runProcess("/usr/bin/osascript", ["-e", script]).ok
    }
}

// MARK: - The lid-closed permission helper (sudoers)

func helperInstalled() -> Bool {
    FileManager.default.fileExists(atPath: Paths.sudoersFile)
}

@discardableResult
func installHelper() -> Bool {
    let user = NSUserName()
    let line = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep *"
    let cmd =
        "printf '%s\\n' '\(line)' > \(Paths.sudoersFile) && chmod 440 \(Paths.sudoersFile) && "
        + "visudo -cf \(Paths.sudoersFile) || (rm -f \(Paths.sudoersFile); false)"
    let script =
        "do shell script \"" + cmd.replacingOccurrences(of: "\"", with: "\\\"")
        + "\" with administrator privileges"
    return runProcess("/usr/bin/osascript", ["-e", script]).ok
}
