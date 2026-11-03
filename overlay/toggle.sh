#!/usr/bin/env bash
# SelfCheckout Rice — CRT overlay toggle (start-or-toggle-visibility).
# Written for the SelfCheckout rice.
#
# First invocation starts the overlay in the background.
# Subsequent invocations send SIGUSR1, which toggles its visibility
# (XMapWindow/XUnmapWindow) without re-initializing GL.
# Bound to Super+F12 via GNOME custom-keybinding.

set -u
BIN="$HOME/rice-selfcheckout/overlay/crt-overlay"
CFG="$HOME/rice-selfcheckout/overlay/config.ini"
LOG="$HOME/.cache/crt-overlay.log"
mkdir -p "$(dirname "$LOG")"

pid=$(pgrep -x crt-overlay | head -1 || true)
if [[ -n "${pid:-}" ]]; then
    kill -USR1 "$pid"
else
    nohup "$BIN" "$CFG" >>"$LOG" 2>&1 &
    disown || true
fi
