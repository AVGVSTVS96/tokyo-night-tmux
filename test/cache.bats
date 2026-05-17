#!/usr/bin/env bats
#
# Unit tests for the shared status-cache helpers (lib/cache.sh).
#
# These tests use a per-test temp HOME so the real ~/.cache is untouched,
# and stub `tmux` via PATH so theme-aware key generation works without a
# running tmux server.

setup() {
  # shellcheck source=../lib/cache.sh
  source "${BATS_TEST_DIRNAME}/../lib/cache.sh"

  export TMPDIR_TEST="$(mktemp -d)"
  export XDG_CACHE_HOME="${TMPDIR_TEST}/cache"
  export HOME="${TMPDIR_TEST}/home"
  mkdir -p "$XDG_CACHE_HOME" "$HOME"

  # Stub `tmux` so _sc_key can read @tokyo-night-tmux_theme without a
  # running server. The active theme is sourced from $STUB_TMUX_THEME.
  export STUB_BIN="${TMPDIR_TEST}/bin"
  mkdir -p "$STUB_BIN"
  cat >"${STUB_BIN}/tmux" <<'EOF'
#!/usr/bin/env bash
# Minimal `tmux show-option -gqv @tokyo-night-tmux_theme` stub.
if [ "$1" = "show-option" ]; then
  case " $* " in
    *" @tokyo-night-tmux_theme "*) printf '%s' "${STUB_TMUX_THEME:-}" ;;
    *) printf '' ;;
  esac
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/tmux"
  export PATH="${STUB_BIN}:${PATH}"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "_sc_dir creates and returns the cache directory" {
  run _sc_dir
  [ "$status" -eq 0 ]
  [ "$output" = "${XDG_CACHE_HOME}/tokyo-night-tmux" ]
  [ -d "$output" ]
}

@test "_sc_key incorporates the active theme name" {
  STUB_TMUX_THEME="night" run _sc_key "/work/repo"
  local key_night="$output"

  STUB_TMUX_THEME="storm" run _sc_key "/work/repo"
  local key_storm="$output"

  STUB_TMUX_THEME="day" run _sc_key "/work/repo"
  local key_day="$output"

  [ -n "$key_night" ]
  [ "$key_night" != "$key_storm" ]
  [ "$key_night" != "$key_day" ]
  [ "$key_storm" != "$key_day" ]
}

@test "_sc_key sanitizes the basename component" {
  STUB_TMUX_THEME="night" run _sc_key "/some/weird path/with$chars!"
  [ "$status" -eq 0 ]
  # Sanitized basename must contain only [A-Za-z0-9._-] after the dash.
  [[ "$output" =~ ^[0-9]+-[A-Za-z0-9._-]+$ ]]
}

@test "_sc_fresh is false for a missing file" {
  run _sc_fresh "${TMPDIR_TEST}/nope" 10
  [ "$status" -ne 0 ]
}

@test "_sc_fresh is true within TTL and false after" {
  local f="${TMPDIR_TEST}/cache.status"
  echo "hi" >"$f"

  run _sc_fresh "$f" 60
  [ "$status" -eq 0 ]

  # Backdate the file's mtime by 120 seconds.
  if stat -f %m "$f" >/dev/null 2>&1; then
    touch -t "$(date -v-2M +%Y%m%d%H%M.%S)" "$f"
  else
    touch -d "2 minutes ago" "$f"
  fi

  run _sc_fresh "$f" 60
  [ "$status" -ne 0 ]
}

@test "_sc_write atomically replaces the target file" {
  local f="${TMPDIR_TEST}/atomic.status"
  echo "original" >"$f"

  printf 'new contents' | _sc_write "$f"
  [ "$(cat "$f")" = "new contents" ]

  # No stale tempfiles left behind.
  run find "${TMPDIR_TEST}" -name 'atomic.status.*' -type f
  [ -z "$output" ]
}

@test "_sc_lock acquires a free lock and blocks a second attempt" {
  local lock="${TMPDIR_TEST}/the.lock"

  run _sc_lock "$lock" 60
  [ "$status" -eq 0 ]
  [ -d "$lock" ]

  run _sc_lock "$lock" 60
  [ "$status" -ne 0 ]
}

@test "_sc_lock reclaims a stale lock older than LOCK_TTL" {
  local lock="${TMPDIR_TEST}/stale.lock"
  mkdir "$lock"

  # Backdate the lock dir by 5 minutes.
  if stat -f %m "$lock" >/dev/null 2>&1; then
    touch -t "$(date -v-5M +%Y%m%d%H%M.%S)" "$lock"
  else
    touch -d "5 minutes ago" "$lock"
  fi

  run _sc_lock "$lock" 60
  [ "$status" -eq 0 ]
  [ -d "$lock" ]
}

@test "_sc_lock does NOT reclaim a fresh lock" {
  local lock="${TMPDIR_TEST}/fresh.lock"
  mkdir "$lock"

  run _sc_lock "$lock" 600
  [ "$status" -ne 0 ]
}

@test "_sc_gc deletes files older than 7 days" {
  local d="${TMPDIR_TEST}/gc"
  mkdir -p "$d"
  local old="${d}/old.status"
  local new="${d}/new.status"
  echo "x" >"$old"
  echo "y" >"$new"

  if stat -f %m "$old" >/dev/null 2>&1; then
    touch -t "$(date -v-8d +%Y%m%d%H%M.%S)" "$old"
  else
    touch -d "8 days ago" "$old"
  fi

  _sc_gc "$d"

  [ ! -f "$old" ]
  [ -f "$new" ]
}
