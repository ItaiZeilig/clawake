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
- **Arch:** universal binary (arm64 + x86_64); runs natively on Apple Silicon and Intel
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
AND the daemon is registered and enabled. **Lid-closed is opt-in (default off)** so
the app is fully functional out of the box on the light layer and never prompts for
approval unless you ask for lid-closed. Turning the app On is never gated on the
helper approval. `disablesleep` is a persistent system setting, so it survives a crash/force-quit;
the app reconciles the real state on launch (`adoptDeepState`) to self-heal anything
left behind. A normal **Quit restores sleep**: `shutdown()` reconciles the real
state and then `releaseAll()` clears `SleepDisabled` (it must not stay set after the
app exits), and `uninstall` resets it through the daemon before unregistering.

## Screen lock and the two editions

Separately from sleep, the app can keep the **display** awake via a
`kIOPMAssertionTypePreventUserIdleDisplaySleep` assertion (no root, auto-released on
process exit). While held, the screen stays on and never idle-locks. This is the
"Don't lock the screen" option: config `preventLock` (default on), applied in
`AppState.tick` only while the app is actually keeping the Mac awake.

Two editions, chosen at build time:
- **Standard** (default): shows the "Don't lock the screen" toggle, on by default.
  The Mac stays awake and unlocked; the user can turn locking back on.
- **Enterprise** (`EDITION=enterprise ./build-app.sh` sets `Info.plist`
  `ClawakeEnterprise = true`, DMG named `Clawake-Enterprise-...`): hides the toggle
  and never prevents locking, so the screen still locks on the corporate schedule.
  `AppState.isEnterprise` reads the plist flag and gates both the UI row and the
  display assertion. Both editions share the bundle id and the helper daemon.

## Architecture (four SwiftPM targets)

Defined in `Package.swift`. Dependencies point inward: the app links `ClawakeCore`
+ `ClawakeShared`; the daemon links `ClawakeShared`; Core and Shared link nothing
(Foundation only). The app and the daemon never link each other, they agree only
through `ClawakeShared`.

```
ClawakeCore     pure logic, no AppKit/SwiftUI, unit-tested   (app depends on it)
ClawakeShared   XPC protocol + constants                     (app + daemon share it)
ClawakeHelper   the root daemon                              (depends on Shared)
Clawake         the menu-bar app                             (depends on Core + Shared)
```

### `Sources/ClawakeCore/` — pure logic (public API, no side effects, no UI)

This target **cannot import AppKit or SwiftUI** (the boundary is compiler-enforced),
and it is covered by `Tests/ClawakeCoreTests/` (run `swift test`).

- `Decision.swift` — `Mode` (on/off), `Decision`, `DecideInput`, and `decide(_:)`:
  the single decision function (off, battery floor, only-on-AC, thermal pause, else
  awake with `deep = lidClosed`).
- `Thermal.swift` — `ThermalLevel`, `atOrAboveCutoff`, `nextThermalPaused`
  (hysteresis latch), `thermalCutoff`, `thermalLabel`.
- `PowerReading.swift` — `PowerReading` + `parsePmsetBatt`.
- `Config.swift` — `Config` (mode, lidClosed, preventLock, pauseOnLowBattery,
  battery{min_percent, only_on_ac}, thermal{protect, cutoff}, notifications,
  didOnboard) with **tolerant decoding** (older config files missing new keys still
  load; `lidClosed` defaults **off**). `Paths`: config at
  `~/.claude/plugins/clawake/config.json`. `loadConfig` / `saveConfig`.

### `Sources/Clawake/` — the app, grouped by feature/layer

- `App/main.swift` — `NSApplication` bootstrap; sets the `AppDelegate`.
- `App/App.swift` — `AppDelegate`. Creates the `NSStatusItem` (car icon), the
  popover, and the Settings window; runs a 5-second `Timer` that calls
  `appState.tick()`; opens the panel on first launch (`!didOnboard`). The app is
  `.accessory` (LSUIElement) the whole time, so **no Dock icon** ever.
- `App/AppState.swift` — the composition root: an `ObservableObject` orchestrator +
  all published UI state (this was `Controller`). `tick()` reads power and thermal,
  computes the `Decision`, applies it, and publishes state (awake, isOn,
  statusTitle/detail, powerText, thermalText/level, lidClosedOn, lidApprovalNeeded,
  the auto-off timer, and the settings mirrors). Setters save config and re-tick.
  `approveLid` registers the `SMAppService` daemon (and opens Login Items if needed).
  `shutdown()` reconciles then releases so Quit restores sleep. `uninstall()` resets
  sleep, unregisters the daemon, deletes the config. `adoptDeepState` (on `power`)
  reconciles a crash-left state.
- `Power/Power.swift` — `PowerController.apply(_:)` (light via IOPMAssertion, deep via
  `setDeep`, single-flight + cooldown; the off-path retries until confirmed).
  `setDeep` calls the privileged daemon over XPC; `helperEnabled()` reports status.
  Owns the `HelperClient`. Also `setKeepDisplayOn` (the "don't lock" assertion).
- `Power/HelperClient.swift` — app side of the daemon: registers/unregisters the
  `SMAppService.daemon(plistName:)` and sends XPC messages (`setSleepDisabled`,
  `ping`) with a short timeout.
- `Power/Sensors.swift` — `readThermal()` (`ProcessInfo.thermalState`), `readPower()`
  (`pmset -g batt`).
- `Power/Shell.swift` — `runProcess(_:_:)` wrapper around `Process`.
- `MenuBar/Popover.swift` — `PanelStyle`, `PopoverController` (an `NSPopover`,
  `.transient`), and `PopoverView` (header, hero On/Off card with the switch + status
  dot, the auto-off countdown, an inline **Approve** banner when lid-closed is on but
  not yet approved, an info block showing **Power / Temperature / Lid closed**, and a
  Settings/Quit footer).
- `Settings/Settings.swift` — the Settings window (also the first-run welcome). Types
  are `SettingsController` / `SettingsView`. Rows: auto-off timer, lid-closed,
  don't-lock (standard build), pause-on-low-battery (+ % pills), only-on-AC, cool-down
  protection (+ Hot/Very-hot pills), Done footer. The window uses
  `NSHostingController.sizingOptions = [.preferredContentSize]` so it **fits its
  content height**. It stays `.accessory`, brought forward with
  `activate(ignoringOtherApps:)` + `orderFrontRegardless()` (never `.regular`).
- `UI/Controls.swift` — custom-drawn `BrandSwitch` (orange On/Off switch) and
  `SegmentedPills` (see the render note below for why these are custom).
- `UI/Icons.swift` — `carIcon(active:)` and `appVersion()`.
- `Support/Render.swift` — `renderPanel` / `renderSettings` (marketing/preview PNGs).

### `Sources/ClawakeShared/HelperProtocol.swift`

The `@objc ClawakeHelperProtocol` XPC interface and shared `HelperConstants` (mach
service name, team id, bundle ids), compiled into both the app and the daemon.

### `Sources/ClawakeHelper/` — the root daemon

- `main.swift` — bootstrap only: an `NSXPCListener` on the mach service.
- `HelperService.swift` — the listener delegate + exported object: verifies each
  connection's code signature (our Developer ID team + app bundle id via
  `SecCodeCheckValidity`) before exposing the interface.
- `SleepManager.swift` — the one privileged operation, `pmset -a disablesleep`,
  isolated from the XPC/security code.

### Build

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

**Signing identity (done).** The release is signed with a **Developer ID
Application** certificate and notarized under an Apple Developer account. The build
takes the identity and a stored `notarytool` credential profile from environment
variables, so no account details are hardcoded.

1. **Sign + notarize (one command):**
   ```
   export DEVID_IDENTITY="Developer ID Application: <Your Name> (<TEAMID>)"
   export NOTARY_PROFILE=<your-notarytool-profile>
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
4. **Universal binary (done).** `build-app.sh` builds `arm64` + `x86_64`
   (`swift build --arch arm64 --arch x86_64`), so the app and helper are fat and run
   natively on Apple Silicon and Intel. DMGs are named without an arch suffix.

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
- **Keep it simple: On / Off.** An earlier "follow Claude sessions" mode was
  deliberately removed; do not reintroduce modes without being asked. There is a
  simple **auto-off timer** (Settings: Until off / 30m / 1h / 2h) that flips the app
  to Off when the countdown ends. It is a live session concept, not persisted; a
  duration also turns the app On. Keep it; it was added at the user's request.
- Adaptive light/dark everywhere (the panel and the Settings window both follow the
  system theme).
</content>
