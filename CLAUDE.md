# CLAUDE.md — Clawake

Guidance for Claude (and humans) working on **Clawake**. Read this first.

## What Clawake is

A tiny **native macOS menu-bar app** (Swift + AppKit + SwiftUI) that keeps a Mac
awake, including **with the lid closed**. It lives only in the menu bar (a small
car icon), has no Dock icon, and is deliberately small (the built app is ~750 KB,
the DMG ~400 KB). It was rewritten from an earlier Electron prototype specifically
to avoid Electron's ~100 MB bloat.

- **Bundle id:** `app.clawake.desktop`
- **Version:** 1.0.0
- **Min macOS:** 13.0 (Ventura)
- **Arch:** built for Apple Silicon (arm64); universal is a later step
- **Support email:** itaizeilig1@gmail.com

## How it keeps the Mac awake (the two layers)

Clawake has two independent power layers. This split is the heart of the app.

1. **Light layer (idle-sleep prevention).** `IOPMAssertionCreateWithName` with
   `kIOPMAssertionTypePreventUserIdleSystemSleep`. No root, no admin, works even
   inside the App Sandbox. This alone keeps the Mac awake while the lid is open.

2. **Deep layer (lid-closed keep-awake).** `pmset -a disablesleep 1` (sets
   `SleepDisabled`). This is what survives a closed lid. It **needs root**, so it
   runs through a **privileged `SMAppService` daemon** (`ClawakeHelper`) embedded in
   the app bundle and reached over **XPC**. The daemon validates the caller's code
   signature (our Developer ID team + app bundle id) before doing anything, then
   runs `pmset` as root. The user approves the daemon **once** in System Settings →
   Login Items & Extensions (no password prompts during use, no `sudoers`). This
   replaced the old `/etc/sudoers.d/clawake` approach entirely.

The deep layer only engages when the user turned the "lid closed" setting **on**
AND the daemon is registered and enabled. Otherwise the app still runs the light
layer, so it is useful out of the box and never prompts unless you ask for
lid-closed. `disablesleep` is a persistent system setting, so it survives the
daemon/app exiting (that is the point); the app reconciles the real state on launch
(`adoptDeepState`) to self-heal anything a crash left behind, and `uninstall`
resets it through the daemon before unregistering.

## Architecture (file by file)

All source is in `Sources/Clawake/`.

- `main.swift` — `NSApplication` bootstrap; sets the `AppDelegate`.
- `App.swift` — `AppDelegate`. Creates the `NSStatusItem` (car icon), the popover,
  and the Settings window; runs a 5-second `Timer` that calls `controller.tick()`;
  opens Settings on first launch (`!didOnboard`). Also `carIcon(active:)` and
  `appVersion()`. The app is `.accessory` (LSUIElement) the whole time, so **no
  Dock icon** ever.
- `Model.swift` — pure logic, no side effects. `Mode` (on/off), `Decision`,
  `decide(_:)` (the single decision function: off, battery floor, only-on-AC,
  thermal pause, else awake with `deep = lidClosed`). Thermal helpers
  (`ThermalLevel`, `atOrAboveCutoff`, `nextThermalPaused` hysteresis latch,
  `thermalCutoff`, `thermalLabel`), and `parsePmsetBatt`.
- `Config.swift` — `Config` (mode, lidClosed, pauseOnLowBattery, battery{min_percent,
  only_on_ac}, thermal{protect, cutoff}, notifications, didOnboard) with **tolerant
  decoding** (older config files missing new keys still load). `Paths`: config at
  `~/.claude/plugins/clawake/config.json`.
- `Controller.swift` — `ObservableObject` orchestrator + all published UI state.
  `tick()` reads power and thermal, computes the `Decision`, applies it, and
  publishes state (awake, isOn, statusTitle/detail, powerText, thermalText/level,
  lidClosedOn, lidApprovalNeeded, and the settings mirrors). Setters save config and
  re-tick. `approveLid` registers the `SMAppService` daemon (and opens Login Items
  if approval is needed), then ticks. `uninstall()` resets sleep, unregisters the
  daemon, and deletes the config. `adoptDeepState` reconciles a crash-left state.
- `Power.swift` — `PowerController.apply(_:)` (light via IOPMAssertion, deep via
  `setDeep`, single-flight + cooldown). `setDeep` now calls the privileged daemon
  over XPC (`helper.setSleepDisabled`); `helperEnabled()` reports the daemon status.
  Owns the `HelperClient`.
- `HelperClient.swift` (app side) — registers/unregisters the `SMAppService` daemon
  (`SMAppService.daemon(plistName:)`) and sends it XPC messages (`setSleepDisabled`,
  `ping`) with a short timeout.
- `Sources/ClawakeShared/HelperProtocol.swift` — the `@objc ClawakeHelperProtocol`
  XPC interface and shared `HelperConstants` (mach service name, team id, bundle
  ids), compiled into both the app and the daemon.
- `Sources/ClawakeHelper/main.swift` — the root daemon: an `NSXPCListener` on the
  mach service that verifies each connection's code signature (our Developer ID team
  + app bundle id via `SecCodeCheckValidity`) before running `pmset` as root.
- `Sensors.swift` — `readThermal()` (`ProcessInfo.thermalState`), `readPower()`
  (`pmset -g batt`).
- `Popover.swift` — the menu-bar panel. `PanelStyle`, custom-drawn `BrandSwitch`
  (orange On/Off switch) and `SegmentedPills` (see the render note below for why
  these are custom), `PopoverController` (an `NSPopover`, `.transient`), and
  `PopoverView` (header, hero On/Off card with the switch + status dot, an inline
  **Approve** banner when lid-closed is on but not yet approved, an info block
  showing **Power / Temperature / Lid closed**, and a Settings/Quit footer).
- `Onboarding.swift` — the Settings window (also the first-run welcome). Note the
  file is named `Onboarding.swift` but the types are `SettingsController` /
  `SettingsView`. Rows: lid-closed, pause-on-low-battery (+ % pills), only-on-AC,
  cool-down protection (+ Hot/Very-hot pills), Done footer. The window uses
  `NSHostingController.sizingOptions = [.preferredContentSize]` so it **fits its
  content height** and re-fits when a section expands. It stays `.accessory` and is
  brought forward with `activate(ignoringOtherApps:)` + `orderFrontRegardless()`
  (never `.regular`, so it adds no Dock icon).
- `Shell.swift` — `runProcess(_:_:)` wrapper around `Process`.
- `build-app.sh` — assembles `Clawake.app` (Info.plist with `LSUIElement`, copies
  the car icons + `AppIcon.icns`), ad-hoc codesigns, and builds the DMG with
  `hdiutil`. Icons come from `~/Documents/cc-caffeine/assets` in the original
  environment; adjust the asset paths if that folder is not present.

## Build and run

```
cd clawake-mac
swift build -c release           # compile (needs Command Line Tools or Xcode)
./build-app.sh                   # assemble Clawake.app + DMG into release/
open release/Clawake.app         # run it (icon appears in the menu bar)
```

Xcode also opens the package directly: `File > Open` the folder (or open
`Package.swift`). There is no `.xcodeproj`; it is a Swift Package.

## Distribution: the important decision (already researched)

**Goal:** ship a version people can install and that Apple trusts.

**Key finding — the App Store is NOT a fit, because of the lid-closed feature.**
Every Mac App Store app must run in the **App Sandbox**, which forbids exactly what
the deep layer needs: shelling out to `sudo`, writing `/etc/sudoers.d/`, running
`osascript` with admin, and running `pmset` as root. There is **no public,
sandbox-safe API** to keep a portable awake with the lid closed and no external
display: the only real routes are `pmset disablesleep` (needs root) or Apple's
private **SkyLight** framework (needs a private entitlement and SIP disabled).
Even Amphetamine, which lists lid-closed on the App Store, **offloads to a separate
out-of-store helper ("Power Protect") on Apple Silicon** to make it work. So the
feature inherently lives outside the sandbox.

**Chosen path: notarized Developer ID DMG (outside the App Store).** It keeps every
feature, and it is still Apple-approved via **notarization** (Gatekeeper trusts it,
opens with no warning). This is where serious lid-closed utilities live
(KeepingYouAwake, Caffeine, etc.).

The light layer (IOPMAssertion) is fully sandbox-safe, so a future App-Store "lite"
build that keeps the Mac awake with the lid **open** (plus the thermal/battery
guards) is possible, but it must drop lid-closed. Not the current priority.

## Next steps (to productionize the notarized DMG)

**Tooling is ready (done).** `build-app.sh` now signs with a Developer ID identity +
hardened runtime + secure timestamp + `Clawake.entitlements`, builds the DMG, and
(when a notary profile is set) submits to Apple and staples both the `.app` and the
`.dmg`. Icons are vendored in `assets/` so the build no longer depends on the old
out-of-repo `cc-caffeine/assets` folder (which is gone). With no identity set it
still ad-hoc signs for local runs. The hardened-runtime signing command and the
entitlements file are verified valid (`flags=0x10000(runtime)`, strict verify passes).

**Signing identity (done): personal Individual account.** The release is signed
under **Developer ID Application: Itai Zeilig (UXXB9YTYKF)**, Apple ID
`itaizeilig1@gmail.com`. The earlier Sosna Moving Ltd (`LZ45Q8WB49`) Developer ID
cert and notary profile were removed on purpose; do not use Sosna to sign Clawake.
A stored notary profile named `clawake-notary` holds the personal credentials.
(A pre-existing *Apple Distribution: Sosna Moving Ltd* cert may still be in the
keychain for unrelated company work; it is not used by Clawake.)

1. **Sign + notarize (one command):**
   ```
   export DEVID_IDENTITY="Developer ID Application: Itai Zeilig (UXXB9YTYKF)"
   export NOTARY_PROFILE=clawake-notary
   ./build-app.sh
   ```
   The script does hardened-runtime sign → DMG → `notarytool submit --wait` →
   `stapler staple` (app + DMG) → Gatekeeper check, all in that run.
2. **Lid helper via `SMAppService` (done).** The privileged layer is a signed
   `SMAppService` daemon (`ClawakeHelper`) embedded in the bundle, reached over XPC
   with code-signature validation. The old sudoers approach is gone. This is the
   Apple-documented mechanism for privileged operations and gives a genuinely clean
   uninstall (the helper lives in the bundle, so trashing the app removes its code;
   `--uninstall` / the daemon `unregister()` clears the registration).
3. **Distribute.** A one-page landing site (free on GitHub Pages) with a Download
   button pointing at a **GitHub Releases** DMG. Add **Sparkle** later for
   auto-updates; a Homebrew Cask is an easy bonus.
4. **Universal binary + icons.** Build `arm64` + `x86_64` if you want Intel support;
   confirm the app icon set is complete.

## Working notes for Claude

- **You cannot screenshot the running GUI** here (Screen Recording is blocked). To
  see a SwiftUI view, render it with `ImageRenderer(content:).nsImage`, composite it
  on an `NSColor` background, write a PNG to `/tmp`, and Read it. `ImageRenderer` is
  `@MainActor`; call it inside `MainActor.assumeIsolated { }` from a delegate method.
- **ImageRenderer gotchas** (why some UI is custom-drawn): native `Toggle`/`Button`
  render as a yellow placeholder box, `ScrollView` content renders blank, and
  `NSViewRepresentable` hangs the renderer. That is why the switch (`BrandSwitch`)
  and the choice control (`SegmentedPills`) are custom-drawn, and why the render
  helper passed `scroll: false`. These controls all work normally when the app runs
  live; the placeholder only appears in the render.
- **Verify guards by breaking them.** When a test or check is supposed to catch a
  bug, break the code and watch it fail before trusting it.

## User preferences (carry these forward)

- **No em dashes** in UI text or prose.
- **Keep it professional**, not "vibe coded". Look at real product designs.
- **Stay tiny and native.** Do not reach for Electron or heavy frameworks.
- **Keep it simple: On / Off.** An earlier "follow Claude sessions" mode and timer
  were deliberately removed. Do not reintroduce modes without being asked.
- Adaptive light/dark everywhere (the panel and the Settings window both follow the
  system theme).
</content>
