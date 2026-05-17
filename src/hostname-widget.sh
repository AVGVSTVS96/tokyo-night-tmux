#!/usr/bin/env bash
#
# Prints the styled hostname segment for the status line. Designed to be
# invoked once at plugin load via $(...) (not #(...)), so the captured
# string is embedded directly into status-right and tmux never forks a
# shell for it on redraw.

SHOW_WIDGET="$(tmux show-option -gqv @tokyo-night-tmux_show_hostname 2>/dev/null || true)"
[ "$SHOW_WIDGET" = "1" ] || exit 0

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/themes.sh
source "$CURRENT_DIR/themes.sh" >/dev/null 2>&1 || exit 0

# Prefer the short hostname; fall back to platform-specific hostname APIs.
# Suppress errors so we exit cleanly on unusual hosts.
if command -v hostname >/dev/null 2>&1; then
  host_name="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
elif command -v hostnamectl >/dev/null 2>&1; then
  host_name="$(hostnamectl hostname 2>/dev/null || true)"
elif command -v scutil >/dev/null 2>&1; then
  host_name="$(scutil --get LocalHostName 2>/dev/null || true)"
else
  host_name="unknown-host"
fi

# tmux's format engine treats `#` as an escape character, so double any
# literal `#` we are about to embed in the status line.
host_name="${host_name//#/##}"

[ -n "$host_name" ] || exit 0

printf '#[nodim,fg=%s]@%s' "${THEME[black]}" "$host_name"
