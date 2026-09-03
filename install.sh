#!/bin/bash
# Installs the Typeless paywall closer into Hammerspoon.
#   ./install.sh            install or update
#   ./install.sh uninstall  remove the symlink and the init.lua block
#
# Idempotent: safe to run again after `git pull`.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="typeless_paywall_closer.lua"
HS_DIR="$HOME/.hammerspoon"
LINK="$HS_DIR/$MODULE"
INIT="$HS_DIR/init.lua"
MARKER='require("typeless_paywall_closer")'

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

uninstall() {
  if [ -L "$LINK" ]; then rm "$LINK"; say "removed $LINK"; fi
  if [ -f "$INIT" ] && grep -qF "$MARKER" "$INIT"; then
    # Drop the block this script added (from its comment line to typeless.start()).
    perl -0pi -e 's/\n?-- typeless-paywall-closer \(added by install\.sh\)\n.*?typeless\.start\(\)\n//s' "$INIT"
    # Fallback for hand-written init.lua files: drop the two essential lines.
    perl -ni -e 'print unless /typeless_paywall_closer"\)|^typeless\.start\(\)/' "$INIT"
    say "removed the typeless block from $INIT"
  fi
  if command -v hs >/dev/null 2>&1; then hs -c 'hs.reload()' >/dev/null 2>&1 || true; fi
  say "done. Hammerspoon itself was left installed."
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

say "opening Hammerspoon"
open -a Hammerspoon
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

cat <<'TXT'

Next steps (one-time):
  1. If macOS asks whether to open Hammerspoon (downloaded from the internet), click Open.
  2. In System Settings > Privacy & Security > Accessibility, turn on Hammerspoon.
  3. Quit and reopen Hammerspoon once. Until you do, it cannot read Typeless.
  4. A "⌧" item appears in the menu bar. Click it to see status or pause.

Log file: ~/Library/Logs/typeless-paywall-closer/activity.log
Update later: git pull, then run ./install.sh again.
TXT
