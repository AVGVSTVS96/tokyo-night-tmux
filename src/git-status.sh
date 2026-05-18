#!/usr/bin/env bash
#
# git-status widget. Two modes:
#
#   * Default: print the cached value (if any) and spawn a detached
#     refresh worker if the cache is stale. The tmux redraw never blocks
#     on git.
#   * --refresh: re-compute under a mutex and atomically replace the
#     cache. Invoked by the default mode in the background.

DIR="${2:-${1:-$PWD}}"
TTL=10
FETCH_TTL=300
LOCK_TTL=120
CACHE_PREFIX="git"

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/cache.sh
source "$CURRENT_DIR/../lib/cache.sh"

CACHE_DIR="$(_sc_dir)" || exit 0
CACHE_KEY="$(_sc_key "$DIR")"
CACHE="$CACHE_DIR/${CACHE_PREFIX}-${CACHE_KEY}.status"
LOCK="$CACHE.lock"

if [ "${1:-}" != "--refresh" ]; then
  [ -f "$CACHE" ] && cat "$CACHE"
  if ! _sc_fresh "$CACHE" "$TTL"; then
    ( "$0" --refresh "$DIR" >/dev/null 2>&1 </dev/null & )
  fi
  exit 0
fi

_sc_lock "$LOCK" "$LOCK_TTL" || exit 0
trap 'rm -rf "$LOCK" 2>/dev/null' EXIT INT TERM
( _sc_gc "$CACHE_DIR" >/dev/null 2>&1 & )

# shellcheck source=src/themes.sh
source "$CURRENT_DIR/themes.sh" >/dev/null 2>&1 || exit 0

ROOT="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT" ]; then
  : | _sc_write "$CACHE"
  exit 0
fi
cd "$ROOT" || exit 0

RESET="#[fg=${THEME[foreground]},bg=${THEME[background]},nobold,noitalics,nounderscore,nodim]"

_tmux_option_or_default() {
  local option="$1" default="$2" value
  value="$(tmux show-option -gqv "$option" 2>/dev/null || true)"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$default"
  fi
}

GIT_CHANGED_ICON="$(_tmux_option_or_default @tokyo-night-tmux_git_changed_icon "")"
GIT_INSERTIONS_ICON="$(_tmux_option_or_default @tokyo-night-tmux_git_insertions_icon "")"
GIT_DELETIONS_ICON="$(_tmux_option_or_default @tokyo-night-tmux_git_deletions_icon "")"
GIT_UNTRACKED_ICON="$(_tmux_option_or_default @tokyo-night-tmux_git_untracked_icon "")"
GIT_DIRTY_ICON="$(_tmux_option_or_default @tokyo-night-tmux_git_dirty_icon "󱓎")"
GIT_PUSH_ICON="$(_tmux_option_or_default @tokyo-night-tmux_git_push_icon "󰛃")"
GIT_PULL_ICON="$(_tmux_option_or_default @tokyo-night-tmux_git_pull_icon "󰛀")"
GIT_CLEAN_ICON="$(_tmux_option_or_default @tokyo-night-tmux_git_clean_icon "")"
GIT_SYNC_MARKER="$(_tmux_option_or_default @tokyo-night-tmux_git_sync_marker "▒")"

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
if [ -z "$BRANCH" ]; then
  : | _sc_write "$CACHE"
  exit 0
fi

DISPLAY_BRANCH="$BRANCH"
if [[ ${#DISPLAY_BRANCH} -gt 25 ]]; then
  DISPLAY_BRANCH="${DISPLAY_BRANCH:0:25}…"
fi

STATUS="$(git status --porcelain 2>/dev/null | grep -cE '^(M| M)' || true)"
STATUS="${STATUS:-0}"
SYNC_MODE=0
NEED_PUSH=0
CHANGED_COUNT=0
INSERTIONS_COUNT=0
DELETIONS_COUNT=0
UNTRACKED_COUNT=0

STATUS_CHANGED=""
STATUS_INSERTIONS=""
STATUS_DELETIONS=""
STATUS_UNTRACKED=""

if [[ $STATUS -ne 0 ]]; then
  read -r CHANGED_COUNT INSERTIONS_COUNT DELETIONS_COUNT < <(
    git diff --numstat 2>/dev/null |
      awk 'NF==3 {changed+=1; ins+=$1; del+=$2} END {printf("%d %d %d", changed, ins, del)}'
  )
  CHANGED_COUNT="${CHANGED_COUNT:-0}"
  INSERTIONS_COUNT="${INSERTIONS_COUNT:-0}"
  DELETIONS_COUNT="${DELETIONS_COUNT:-0}"
  SYNC_MODE=1
fi

UNTRACKED_COUNT="$(git ls-files --other --exclude-standard 2>/dev/null | wc -l | tr -d ' ')"
UNTRACKED_COUNT="${UNTRACKED_COUNT:-0}"

if [[ $CHANGED_COUNT -gt 0 ]]; then
  STATUS_CHANGED="${RESET}#[fg=${THEME[yellow]},bg=${THEME[background]},bold]${GIT_CHANGED_ICON} ${CHANGED_COUNT} "
fi

if [[ $INSERTIONS_COUNT -gt 0 ]]; then
  STATUS_INSERTIONS="${RESET}#[fg=${THEME[green]},bg=${THEME[background]},bold]${GIT_INSERTIONS_ICON} ${INSERTIONS_COUNT} "
fi

if [[ $DELETIONS_COUNT -gt 0 ]]; then
  STATUS_DELETIONS="${RESET}#[fg=${THEME[red]},bg=${THEME[background]},bold]${GIT_DELETIONS_ICON} ${DELETIONS_COUNT} "
fi

if [[ $UNTRACKED_COUNT -gt 0 ]]; then
  STATUS_UNTRACKED="${RESET}#[fg=${THEME[black]},bg=${THEME[background]},bold]${GIT_UNTRACKED_ICON} ${UNTRACKED_COUNT} "
fi

# Run `git fetch` at most once per FETCH_TTL seconds. Network I/O — only
# safe because we are in the detached refresh path, never on the redraw
# critical path.
_maybe_fetch() {
  local fetch_head m n
  fetch_head="$(git rev-parse --git-path FETCH_HEAD 2>/dev/null)" || return 0
  n="$(date +%s)"
  if [ -f "$fetch_head" ]; then
    m="$(_sc_mtime "$fetch_head")"
  else
    m=0
  fi
  m="${m:-0}"
  if [ "$((n - m))" -gt "$FETCH_TTL" ]; then
    git fetch --atomic origin --negotiation-tip=HEAD >/dev/null 2>&1 || \
      git fetch origin >/dev/null 2>&1 || true
  fi
}

if [[ $SYNC_MODE -eq 0 ]]; then
  NEED_PUSH="$(git log '@{push}..' --oneline 2>/dev/null | wc -l | tr -d ' ')"
  NEED_PUSH="${NEED_PUSH:-0}"
  if [[ $NEED_PUSH -gt 0 ]]; then
    SYNC_MODE=2
  else
    _maybe_fetch
    REMOTE_DIFF="$(git diff --numstat "$BRANCH" "origin/${BRANCH}" 2>/dev/null)"
    if [[ -n $REMOTE_DIFF ]]; then
      SYNC_MODE=3
    fi
  fi
fi

# Status indicator: a colored marker plus a sync-state nerd-font glyph.
# Glyphs can be overridden from tmux.conf with @tokyo-night-tmux_git_* options.
case "$SYNC_MODE" in
1)
  REMOTE_STATUS="$RESET#[bg=${THEME[background]},fg=${THEME[bred]},bold]${GIT_SYNC_MARKER} ${GIT_DIRTY_ICON}"
  ;;
2)
  REMOTE_STATUS="$RESET#[bg=${THEME[background]},fg=${THEME[red]},bold]${GIT_SYNC_MARKER} ${GIT_PUSH_ICON}"
  ;;
3)
  REMOTE_STATUS="$RESET#[bg=${THEME[background]},fg=${THEME[magenta]},bold]${GIT_SYNC_MARKER} ${GIT_PULL_ICON}"
  ;;
*)
  REMOTE_STATUS="$RESET#[bg=${THEME[background]},fg=${THEME[green]},bold]${GIT_SYNC_MARKER} ${GIT_CLEAN_ICON}"
  ;;
esac

printf '%s' "$REMOTE_STATUS $RESET$DISPLAY_BRANCH $STATUS_CHANGED$STATUS_INSERTIONS$STATUS_DELETIONS$STATUS_UNTRACKED" | _sc_write "$CACHE"
