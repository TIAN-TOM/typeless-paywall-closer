<div align="center">

# Typeless Paywall Closer

**Keeps the Typeless floating bar clear of upgrade nudges. Nothing else is touched.**

[![Platform](https://img.shields.io/badge/platform-macOS-000000?logo=apple&logoColor=white)](#requirements)
[![Runs on Hammerspoon](https://img.shields.io/badge/runs%20on-Hammerspoon-4c9be8)](https://www.hammerspoon.org)
[![Verified on Typeless 2.5.0](https://img.shields.io/badge/verified%20on-Typeless%202.5.0-2f7d32)](#verified-behaviour)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](LICENSE)

English · [简体中文](README.zh-CN.md)

</div>

---

Typeless Paywall Closer is a small, auditable macOS utility that dismisses the two paywall cards
Typeless shows in its floating bar, **"Upgrade for enhanced accuracy"** and **"High demand"**,
the moment they render. It uses the macOS Accessibility API to press the card's own close button,
exactly as you would. It does not patch the app, intercept traffic, or talk to the network.

The trade-off is honest: the card is visible for a fraction of a second before it goes away,
typically under 0.2 s. In exchange you keep an unmodified Typeless, survive app updates, and can
read every line of what runs on your machine.

## Highlights

- **Surgical.** Matches two exact titles. Update notices, errors and every other card are left alone.
- **Non-invasive.** No `app.asar` patching, no code-signing games, no local proxy. Typeless updates keep working as long as the card layout does.
- **Always on.** A launchd agent supervises Hammerspoon: if it quits or crashes it is back within seconds, and it starts at login.
- **Battery aware.** Scans every 0.05 s only while the microphone is in use (and for 30 s after). Idle, it checks every 2 s.
- **Observable.** A menu-bar item shows permission state, attachment, scan mode and the last close. A log records only closes, warnings and lifecycle events.
- **Self-checking.** A built-in self-test runs at every start and exercises the matcher and scheduler with synthetic data.
- **Private by design.** Text read from the floating bar is compared with the target titles and discarded. Nothing is stored or sent.

## Quick start

Requires macOS and [Homebrew](https://brew.sh).

```bash
git clone https://github.com/TIAN-TOM/typeless-paywall-closer.git && cd typeless-paywall-closer && ./install.sh
```

The installer:

1. Installs Hammerspoon via Homebrew if it is missing.
2. Symlinks the script into `~/.hammerspoon` and appends a start-up block to `init.lua`.
3. Renders and loads the launchd agent `org.hammerspoon.keepalive`, then hands Hammerspoon over to launchd.
4. Opens the Accessibility pane of System Settings.

Then, once:

1. If macOS asks whether to open Hammerspoon, click **Open**.
2. In **System Settings › Privacy & Security › Accessibility**, enable **Hammerspoon**.
3. Quit and reopen Hammerspoon. Until you do, the Accessibility API refuses requests to an already-running Typeless.

A `⌧` item appears in the menu bar. That is the whole product.

**Update:** `git pull`, then `./install.sh` again. **Uninstall:** `./install.sh uninstall` (Hammerspoon itself stays).
**Skip the launchd agent:** `KEEPALIVE=0 ./install.sh`; Hammerspoon then relies on its login item only.

<details>
<summary>Manual installation</summary>

```bash
brew install --cask hammerspoon
ln -s "$PWD/typeless_paywall_closer.lua" ~/.hammerspoon/typeless_paywall_closer.lua
```

Add to `~/.hammerspoon/init.lua`:

```lua
require("hs.ipc")
hs.autoLaunch(true)
typeless = require("typeless_paywall_closer")
typeless.start()
```

Optional but recommended, the launchd supervisor:

```bash
sed "s|__HOME__|$HOME|g" launchd/org.hammerspoon.keepalive.plist > ~/Library/LaunchAgents/org.hammerspoon.keepalive.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/org.hammerspoon.keepalive.plist
```

Grant Accessibility to Hammerspoon in System Settings, then **quit and reopen Hammerspoon once**.
Without the restart every AX request to Typeless returns "The accessibility API is disabled".

</details>

## Requirements

| | |
|---|---|
| OS | macOS (tested on macOS 26 / Darwin 25) |
| Runtime | [Hammerspoon](https://www.hammerspoon.org), installed by `install.sh` |
| Target | Typeless desktop, bundle id `now.typeless.desktop`, verified on 2.5.0 |
| Permission | Accessibility, granted to Hammerspoon |

## Menu bar

The `⌧` item exposes everything you need day to day:

- **Enabled / Paused.** Pausing stops scanning; the process stays attached.
- **Status lines.** Accessibility granted or missing, Typeless attached (with pid) or not running, current scan mode, last close and closes this session.
- **Actions.** Scan now, Dump AX tree to console, Open log file, Open Accessibility settings (when missing), Reload Hammerspoon.

The icon changes to `⌧∙` while paused.

## Staying alive

Hammerspoon itself can be quit by hand, killed by a memory-pressure event, or simply not relaunched after
a crash. A login item only fires at login, so a daytime exit leaves you without cover until the next
restart. The installer therefore registers a user LaunchAgent:

| Setting | Value |
|---|---|
| Label | `org.hammerspoon.keepalive` |
| File | `~/Library/LaunchAgents/org.hammerspoon.keepalive.plist`, rendered from [`launchd/`](launchd/) |
| Behaviour | `RunAtLoad` + `KeepAlive`, restart throttle 5 s |
| launchd output | `~/Library/Logs/typeless-paywall-closer/hammerspoon-launchd.log` |

Consequences worth knowing:

- **Quit** from the Hammerspoon menu is undone within seconds. To stop it for real:

  ```bash
  launchctl bootout gui/$(id -u)/org.hammerspoon.keepalive
  ```

- To bring it back:

  ```bash
  launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/org.hammerspoon.keepalive.plist
  ```

- **Reload Config** is unaffected. It reloads Lua inside the running process.
- If Hammerspoon crashes on start, launchd retries every 5 s; the launchd log shows why.

## Privacy and security

The script needs the Accessibility permission, which in principle lets it read any app's UI.
In practice it reads the text of the Typeless floating-bar window only to compare it with the target
titles, then discards it. During dictation the bar may show a live transcript. That text is never
logged, stored or transmitted. The activity log contains only the matched title, the close button's
frame and a timestamp.

The script makes no network requests and writes nothing except its own log file.
It is about 650 lines of Lua and is meant to be read before it is trusted.

## How it works

1. **Attach.** Find the Typeless process by bundle id and set `AXManualAccessibility = true` on its
   application element. Without it Chromium does not expose web content in the accessibility tree.
   Every AX call carries a 1 s timeout, so a wedged Typeless cannot stall Hammerspoon.
2. **Poll.** Chromium emits no usable AX notifications for content changes (90 notification types were
   registered and none arrived). Scanning cadence follows the microphone: while any input device is in
   use, and for 30 s afterwards, scan every 0.05 s; otherwise every 2 s. Paywall cards only arrive in the
   response to a dictation, so idle time is not worth fast polling.
3. **Pick the window.** Only windows whose subrole is `AXDialog` are scanned. The floating bar is an
   Electron panel titled "Status", 750×500, with a dozen nodes when idle. The settings, login and
   onboarding windows are `AXStandardWindow` and are skipped outright. Windows with no subrole fall back
   to a width check (≤ 900 px).
4. **Find the card.** Locate an `AXStaticText` whose value equals a target title, then climb to the
   enclosing `AXUserInterfaceTooltip` container (the HTML `role="tooltip"` card). Buttons are searched
   only inside that container.
5. **Press the X.** A candidate must support `AXPress`, be unnamed or named close / dismiss / x / ×,
   and be at most 40 px on a side. With several candidates the one nearest the container's top-right
   corner wins. Text buttons such as "Upgrade" never qualify. Mouse simulation is off by default;
   `clickFallback = true` enables it only if `AXPress` is refused.

All thresholds live in the `config` table at the top of `typeless_paywall_closer.lua` and can be
changed at runtime through `typeless.config`.

## Verified behaviour

Observed on Typeless 2.5.0, 2026-09-03:

- The card copy is not in the local bundle. The server attaches an `important_notification` to the
  `/ai/voice_flow` response, shaped `{type: "paywall", display: {title, description, icon}, behavior, actions}`.
  `icon` is `diamond` (Upgrade for enhanced accuracy) or `sandglass` (High demand). Editing strings in
  `app.asar` therefore does nothing; neutering the two `paywall` call sites works but means patching,
  re-signing and redoing it after every update. This project deliberately does not go there.
- The card is a MUI Tooltip. When `closable`, an `IconButton` with a 16 px `CloseIcon` and no `aria-label`
  sits in the top-right corner. Both cards share the structure.
- `AXEnhancedUserInterface` and `AXManualAccessibility` are the same switch; setting the former to false
  collapses the whole tree.
- Real cards were closed repeatedly via `AXPress` on a 16×16 button inside a tooltip container.
  The mouse fallback has never fired.
- `targetTitles` also lists the 2.4.0-era titles `Get unlimited words` / `获取无限字数`, reported by
  typeless-plusplus and never seen here. Matching is exact on the whole title, so they are harmless.

## Troubleshooting

| Symptom | Check |
|---|---|
| Cards are not closed | `pgrep -x Hammerspoon`. If nothing, `launchctl print gui/$(id -u)/org.hammerspoon.keepalive` and the launchd log. |
| Menu says *Accessibility: missing* | Enable Hammerspoon in System Settings › Privacy & Security › Accessibility, then quit and reopen Hammerspoon. |
| Menu says *Typeless: not running* | Typeless is not running or its bundle id changed. `hs -c 'typeless.dump()'` lists what is visible. |
| Typeless updated and cards stay | `hs -c 'typeless.dump()'` while a card is showing, then adjust `config`, `alertContainer` or `M.matcher.chooseCloseButton`. New copy goes into `targetTitles`; finish with `hs -c 'typeless.selfTest()'`. |
| Typeless UI in another language | Paywall copy is served per account language. Add that language's titles to `targetTitles`. |

Debug helpers, from a shell with `hs.ipc` loaded:

```bash
hs -c 'typeless.dump()'
```

```bash
hs -c 'typeless.selfTest()'
```

```bash
hs -c 'typeless.micInUse()'
```

```bash
hs -c 'typeless.log.setLogLevel("debug")'
```

⌃⌥⌘T (Control+Option+Command+T) opens the console and dumps once. A successful close logs
`closed "…" via AXPress`.

## Alternatives

| Project | Approach | Platform | Trade-off |
|---|---|---|---|
| [JeasonKim/typeless-paywall-gateway](https://github.com/JeasonKim/typeless-paywall-gateway) | Points the hidden `__DEV_API_HOST` setting at a local proxy that rewrites `paywall` notifications | macOS, Windows | Cards never appear and no Accessibility permission is needed, but all voice and transcript traffic flows through the proxy, it depends on a hidden switch the vendor can remove, and it needs Node and pnpm |
| [Ayndpa/typeless-popup-remover](https://github.com/Ayndpa/typeless-popup-remover) | Patches `app.asar` so the card renderer returns early, disables Electron integrity checks | Windows | Cards never appear, but the app binary is modified and must be re-patched after every update |
| [timmyagentic/typeless-plusplus](https://github.com/timmyagentic/typeless-plusplus) | Native Swift menu-bar app that presses the X via the accessibility tree, plus account and quota tooling | macOS | Open source, MIT, notarised; but the source does not set `AXManualAccessibility` and the author notes real cards are unverified |
| [Jia131313/typeless-toolkit](https://github.com/Jia131313/typeless-toolkit) | Replaces the two `paywall` call sites in `app.asar` with same-length no-ops, fixes integrity data, re-signs | macOS, Windows | Most-starred in the ecosystem, with multi-account, dictionary sync and device reset on top; cards never appear, but the binary is modified and re-patched per update |
| [liuxiaoyu-fiveleven/Typeless-AD-Skipper](https://github.com/liuxiaoyu-fiveleven/Typeless-AD-Skipper) | Finds the card in the accessibility tree and presses X, same route as this project | macOS | Closed source, ad-hoc signed, not notarised, binary contains anti-debugging logic |

This project takes the "dismiss after render" route because it has the smallest trust surface:
no binary patching, no traffic interception. If the brief flash is unacceptable, gateway and toolkit
are the open-source options that prevent the card entirely, at the cost of a proxy or a patched app.

## Repository layout

| Path | Purpose |
|---|---|
| `typeless_paywall_closer.lua` | The whole product. `~/.hammerspoon/typeless_paywall_closer.lua` symlinks here; `hs.reload()` picks up edits |
| `install.sh` | Install, update, uninstall. Idempotent |
| `launchd/org.hammerspoon.keepalive.plist` | LaunchAgent template; `__HOME__` is rendered by the installer |
| `init.lua.example` | Reference `~/.hammerspoon/init.lua` |
| `tools/asar_scan.js` | Grep Typeless's `app.asar` in place and print context |
| `tools/asar_extract.js` | Extract `dist/` from `app.asar` into `./typeless_dist/` |
| `tools/cgwin.swift` | List Typeless windows via CGWindowList, no Accessibility permission needed |
| `docs/retrospective.md` | Investigation and implementation notes (Chinese) |
| `CHANGELOG.md` | Release notes |

Logs: `~/Library/Logs/typeless-paywall-closer/activity.log` (script) and `hammerspoon-launchd.log` (launchd).

## Contributing

Issues and pull requests are welcome, particularly dumps of the accessibility tree after a Typeless
update, and target titles for other interface languages. Run `hs -c 'typeless.selfTest()'` before
opening a pull request; it must report all checks passed.

## License

[MIT](LICENSE).
