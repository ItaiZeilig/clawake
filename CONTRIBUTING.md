# Contributing to Clawake

Thanks for your interest in Clawake, a tiny native macOS menu bar app that keeps your
Mac awake, including with the lid closed. Issues and pull requests are welcome.

## Philosophy

Clawake is deliberately simple: one On/Off switch, an auto-off timer, and a few guards.
Please help keep it that way.

- Keep it **tiny and native** (Swift + AppKit + SwiftUI). No Electron or heavy frameworks.
- Keep the interface simple. An earlier "modes" feature was removed on purpose. Open an
  issue to discuss before adding new modes or settings.
- **No em dashes** in UI text or prose.
- Support **light and dark mode** everywhere.

## Building

Clawake is a Swift package (there is no `.xcodeproj`).

```sh
git clone https://github.com/ItaiZeilig/clawake.git
cd clawake
swift build -c release      # compile
swift test                  # run the unit tests
./build-app.sh              # assemble Clawake.app + DMG into release/
open release/Clawake.app     # run it (icon appears in the menu bar)
```

Xcode can open the folder directly (`File > Open`, or open `Package.swift`). Building does
not require any signing setup; `build-app.sh` ad-hoc signs for local runs.

## Project layout

Four SwiftPM targets, with dependencies pointing inward toward pure logic:

- **ClawakeCore** - pure logic (decisions, thermal, config), no AppKit/SwiftUI, unit-tested
- **ClawakeShared** - the XPC protocol + constants, shared by the app and the daemon
- **ClawakeHelper** - the privileged root daemon (lid-closed keep-awake)
- **Clawake** - the menu bar app (App / Power / MenuBar / Settings / UI)

See [`CLAUDE.md`](CLAUDE.md) for a full file-by-file tour of the architecture.

## Tests

Pure logic lives in `ClawakeCore` and is covered by `Tests/ClawakeCoreTests`. Run
`swift test`. Please add tests for logic changes, especially anything touching the
decision function or the battery/thermal guards.

## Pull requests

- Branch from `main`, keep changes focused, and explain the why.
- Match the surrounding code style (comment density, naming, idioms).
- Make sure `swift build` and `swift test` pass.
- If you change user-facing behavior, update the `README.md` and `CLAUDE.md`.

## Releases (maintainers only)

Signed, notarized releases need a Developer ID identity and a stored `notarytool` profile:

```sh
export DEVID_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="your-notarytool-profile"
./build-app.sh
```

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
