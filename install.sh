#!/bin/bash
# Installs the Typeless paywall closer into Hammerspoon.
#   ./install.sh            install or update
#   ./install.sh uninstall  remove the symlink, the init.lua block and the launchd agent
#
#   KEEPALIVE=0 ./install.sh   skip the launchd agent (Hammerspoon then relies on its login item)
#
# Idempotent: safe to run again after `git pull`.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="typeless_paywall_closer.lua"
HS_DIR="$HOME/.hammerspoon"
LINK="$HS_DIR/$MODULE"
INIT="$HS_DIR/init.lua"
MARKER='require("typeless_paywall_closer")'
AGENT_LABEL="org.hammerspoon.keepalive"
AGENT_SRC="$REPO_DIR/launchd/$AGENT_LABEL.plist"
AGENT_DST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
AGENT_DOMAIN="gui/$(id -u)"
KEEPALIVE="${KEEPALIVE:-1}"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

agent_loaded() { launchctl print "$AGENT_DOMAIN/$AGENT_LABEL" >/dev/null 2>&1; }

# Render the plist template, load it, and hand the Hammerspoon process to launchd.
install_keepalive() {
  [ -f "$AGENT_SRC" ] || die "$AGENT_SRC not found."
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/typeless-paywall-closer"
  local rendered
  rendered="$(sed "s|__HOME__|$HOME|g" "$AGENT_SRC")"
  if agent_loaded && [ -f "$AGENT_DST" ] && [ "$rendered" = "$(cat "$AGENT_DST")" ]; then
    say "launchd agent already loaded and up to date"
    return
  fi
  printf '%s\n' "$rendered" > "$AGENT_DST"
  plutil -lint "$AGENT_DST" >/dev/null || die "rendered plist is invalid: $AGENT_DST"
  if agent_loaded; then launchctl bootout "$AGENT_DOMAIN/$AGENT_LABEL" 2>/dev/null || true; fi
  # A Hammerspoon started by hand is not tracked by launchd; replace it with one that is.
  if pgrep -x Hammerspoon >/dev/null; then
    osascript -e 'tell application "Hammerspoon" to quit' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5; do pgrep -x Hammerspoon >/dev/null || break; sleep 1; done
  fi
  launchctl bootstrap "$AGENT_DOMAIN" "$AGENT_DST"
  say "loaded launchd agent $AGENT_LABEL (Hammerspoon restarts itself if it quits)"
}

remove_keepalive() {
  if agent_loaded; then
    launchctl bootout "$AGENT_DOMAIN/$AGENT_LABEL" 2>/dev/null || true
    say "unloaded launchd agent $AGENT_LABEL"
  fi
  if [ -f "$AGENT_DST" ]; then rm "$AGENT_DST"; say "removed $AGENT_DST"; fi
}

uninstall() {
  remove_keepalive
  if [ -L "$LINK" ]; then rm "$LINK"; say "removed $LINK"; fi
  if [ -f "$INIT" ] && grep -qF "$MARKER" "$INIT"; then
    # Drop the block this script added (from its comment line to typeless.start()).
    perl -0pi -e 's/\n?-- typeless-paywall-closer \(added by install\.sh\)\n.*?typeless\.start\(\)\n//s' "$INIT"
    # Fallback for hand-written init.lua files: drop the two essential lines.
    perl -ni -e 'print unless /typeless_paywall_closer"\)|^typeless\.start\(\)/' "$INIT"
    say "removed the typeless block from $INIT"
  fi
  if command -v hs >/dev/null 2>&1; then hs -c 'hs.reload()' >/dev/null 2>&1 || true; fi
  say "done. Hammerspoon itself was left installed; unloading the agent quit it, reopen it if you still use it."
  exit 0
}

[ "${1:-}" = "uninstall" ] && uninstall

[ "$(uname)" = "Darwin" ] || die "macOS only."
[ -f "$REPO_DIR/$MODULE" ] || die "$MODULE not found next to this script."

if ! command -v brew >/dev/null 2>&1; then
  die "Homebrew is required. Install it from https://brew.sh and run this script again."
fi

if [ -d "/Applications/Hammerspoon.app" ]; then
  say "Hammerspoon already installed"
else
  say "installing Hammerspoon via Homebrew"
  brew install --cask hammerspoon
fi

mkdir -p "$HS_DIR"

if [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$REPO_DIR/$MODULE" ]; then
  say "symlink already points at this checkout"
else
  if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
    mv "$LINK" "$LINK.bak.$(date +%Y%m%d%H%M%S)"
    warn "existing $MODULE moved aside as a .bak file"
  fi
  ln -sfn "$REPO_DIR/$MODULE" "$LINK"
  say "linked $LINK -> $REPO_DIR/$MODULE"
fi

if [ -f "$INIT" ] && grep -qF "$MARKER" "$INIT"; then
  say "init.lua already loads the module"
else
  cat >> "$INIT" <<'LUA'

-- typeless-paywall-closer (added by install.sh)
require("hs.ipc")   -- enables the `hs` command-line tool
hs.autoLaunch(true) -- start Hammerspoon at login
typeless = require("typeless_paywall_closer")
typeless.start()
LUA
  say "appended the typeless block to $INIT"
fi

if [ "$KEEPALIVE" = "1" ]; then
  install_keepalive
else
  warn "KEEPALIVE=0: skipping the launchd agent"
  say "opening Hammerspoon"
  open -a Hammerspoon
fi
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

cat <<'TXT'

Next steps (one-time):
  1. If macOS asks whether to open Hammerspoon (downloaded from the internet), click Open.
  2. In System Settings > Privacy & Security > Accessibility, turn on Hammerspoon.
  3. Quit and reopen Hammerspoon once. Until you do, it cannot read Typeless.
  4. A "⌧" item appears in the menu bar. Click it to see status or pause.

Hammerspoon is supervised by launchd (org.hammerspoon.keepalive): if it quits or
crashes it comes back within seconds. To stop it for real:
  launchctl bootout gui/$(id -u)/org.hammerspoon.keepalive

Log file: ~/Library/Logs/typeless-paywall-closer/activity.log
Update later: git pull, then run ./install.sh again.
TXT
