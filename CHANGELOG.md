# Changelog

All notable changes to this project are documented here. Dates are Australia/Sydney.

## Unreleased

### Added
- `pressDelay` config: wait a set number of seconds after spotting a card before pressing X, so the entrance animation can finish and the dismissal looks less abrupt. Default 0 keeps the old behaviour.
- launchd LaunchAgent `org.hammerspoon.keepalive` that starts Hammerspoon at login and relaunches it within seconds if it quits or crashes. Installed by `install.sh`, removed by `install.sh uninstall`, skipped with `KEEPALIVE=0`.
- `CHANGELOG.md` and a Chinese README (`README.zh-CN.md`).

### Changed
- Fast polling now runs every 0.05 s (was 0.15 s) and keeps going for 30 s after the microphone goes quiet (was 10 s), cutting the visible flash and covering slow server responses.
- `install.sh` hands the Hammerspoon process to launchd instead of opening it directly.
- README rewritten in English with the Chinese version alongside.

## 2026-09-03

### Added
- Hammerspoon script that dismisses the "Upgrade for enhanced accuracy" card via `AXPress` on the card's own close button.
- "High demand" card support, `AXPress` capability check, menu-bar status item, activity log, start-up self-test.
- Adaptive polling driven by microphone use, 1 s timeouts on every AX call, safer defaults (no mouse simulation unless `clickFallback` is set).
- Window selection by AX subrole (`AXDialog` only) instead of width.
- One-command installer, MIT license, investigation retrospective, comparison with other projects, 2.4.0-era titles.
