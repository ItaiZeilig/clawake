# Clawake

**Keep your Mac awake with the lid closed.**

Clawake is a tiny native macOS menu bar app. Close the lid and your session keeps
running: a Claude Code run, a build, a server, or a remote connection stays alive
while the Mac is shut in your bag or on your desk.

- **Website:** https://itaizeilig.github.io/clawake/
- **Download:** [latest release](https://github.com/ItaiZeilig/clawake/releases/latest) (notarized DMG)
- **Requires:** macOS 13 (Ventura) or later, Apple Silicon

## What it does

- Keeps macOS awake with the lid **open** via an `IOPMAssertion` (no root).
- Optionally keeps it awake with the lid **closed** via a signed **`SMAppService`**
  privileged daemon reached over XPC (no `sudoers`, no password prompts during use).
  You approve it once under System Settings → General → Login Items & Extensions.
- Menu bar only, no Dock icon, under ~1 MB.
- Optional guards: pause on low battery, keep awake only on AC power, and cool-down
  (thermal) protection.
- Single instance, self-healing sleep state, and a clean uninstall.

Works alongside a corporate screen-lock policy: the screen still locks on your
company's schedule while the session keeps running behind the lock.

## Install

Open the DMG and drag Clawake to Applications. The build is notarized by Apple
(Developer ID), so it opens with no Gatekeeper warning.

## Build from source

```
swift build -c release      # compile
./build-app.sh              # assemble Clawake.app + DMG into release/
```

To produce a signed, notarized release, set your Developer ID identity and a stored
`notarytool` profile first (see `CLAUDE.md`).

## License

All rights reserved. See [LICENSE](LICENSE). The source is public for transparency;
it is **not** open source and may not be reused. The compiled app is free to
download and use.
