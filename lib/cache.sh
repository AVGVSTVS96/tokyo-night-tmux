#!/usr/bin/env bash
#
# Shared status-cache helpers for tokyo-night-tmux widgets.
#
# Pattern: tmux invokes a widget script via #(...) on every status-interval
# tick. To keep the tmux event loop responsive even when the widget needs to
# run slow git or network calls, each widget:
#
#   1. On normal invocation: print the cached value (if any) and return
#      immediately. If the cache is stale, spawn a detached background
#      worker (`$0 --refresh ...`) and exit. The redraw never blocks on
#      I/O.
#   2. In the --refresh path: acquire a mkdir-based lock (with stale-lock
#      recovery), compute the fresh value, atomically replace the cache
#      file via tmp+rename. Subsequent ticks see the new value.
#
# The cache key incorporates the active theme name so theme switches don't
# show stale colors — when the user changes @tokyo-night-tmux_theme, the
# cache filename changes and a fresh refresh kicks in.

# Cache directory under $XDG_CACHE_HOME (or ~/.cache) for this plugin.
_sc_dir() {
  local d="${XDG_CACHE_HOME:-$HOME/.cache}/tokyo-night-tmux"
  mkdir -p "$d" 2>/dev/null || return 1
  printf '%s' "$d"
}

# Build a stable, theme-aware cache key from a path. We CRC the (theme,path)
# pair so theme switches invalidate cached colorized output, then append a
# sanitized basename for human-readable filenames.
_sc_key() {
  local path="$1" theme sum name
  theme="$(tmux show-option -gqv @tokyo-night-tmux_theme 2>/dev/null)"
  sum="$(printf '%s|%s' "$theme" "$path" | cksum | awk '{print $1}')"
  name="$(basename "$path" | tr -c 'A-Za-z0-9._-' '_')"
  printf '%s-%s' "$sum" "$name"
}

# Cross-platform mtime in seconds since epoch (BSD stat first, GNU stat fallback).
_sc_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# True if file exists and is younger than $2 seconds.
_sc_fresh() {
  [ -f "$1" ] || return 1
  local m n
  m="$(_sc_mtime "$1")"
  [ -n "$m" ] || return 1
  n="$(date +%s)"
  [ "$((n - m))" -lt "$2" ]
}

# Atomically replace $1 with stdin via a sibling tempfile + rename.
# Readers of the cache file therefore see either the old contents or the
# new contents — never a partial write.
_sc_write() {
  local f="$1" t
  t="$(mktemp "${f}.XXXXXX")" || return 1
  cat >"$t"
  mv -f "$t" "$f" 2>/dev/null || { rm -f "$t"; return 1; }
}

# Acquire a lock by creating the directory $1. mkdir is POSIX-atomic, so
# this acts as a mutex. If the lock dir already exists but is older than
# $2 seconds, treat it as stale (the previous worker crashed) and reclaim
# it.
_sc_lock() {
  mkdir "$1" 2>/dev/null && return 0
  [ -d "$1" ] || return 1
  local m n
  m="$(_sc_mtime "$1")"
  n="$(date +%s)"
  if [ -n "$m" ] && [ "$((n - m))" -gt "${2:-120}" ]; then
    rm -rf "$1" 2>/dev/null || return 1
    mkdir "$1" 2>/dev/null && return 0
  fi
  return 1
}

# Best-effort GC of cache files not touched in the last 7 days. Cheap and
# only invoked from the refresh path so it never adds latency to a redraw.
_sc_gc() {
  [ -n "$1" ] || return 0
  find "$1" -type f -mtime +7 -delete 2>/dev/null || true
}
