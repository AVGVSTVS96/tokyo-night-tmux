#!/usr/bin/env bash
#
# wb-git-status (workbench / forge) widget. Shows PR / review / issue /
# bug counts from GitHub or GitLab. Network I/O is fully isolated behind
# the shared status-cache: redraws never block on `gh` or `glab`, and
# slow CLI calls in the background are killed by `timeout`.

DIR="${2:-${1:-$PWD}}"
TTL=300
LOCK_TTL=300
CACHE_PREFIX="wbg"

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/cache.sh
source "$CURRENT_DIR/../lib/cache.sh"
# shellcheck source=lib/parse-remote.sh
source "$CURRENT_DIR/../lib/parse-remote.sh"

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

# Cap any individual CLI call so a hung network can't stall the refresh
# worker. The lock-stale recovery would eventually unblock things, but it's
# cheaper to fail fast and keep the previous cache value.
_timeout_cmd() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 8 "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout 8 "$@"
  else
    "$@"
  fi
}

# On CLI/API failure, prefer "keep stale cache" over "blank widget" to
# avoid visual flicker. Touching the file resets its mtime so we don't
# immediately try to refresh again on the next tick.
_sc_keep_or_blank() {
  if [ -f "$CACHE" ]; then
    touch "$CACHE" 2>/dev/null || true
  else
    : | _sc_write "$CACHE"
  fi
  exit 0
}

ROOT="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT" ]; then
  : | _sc_write "$CACHE"
  exit 0
fi
cd "$ROOT" || exit 0

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
if [ -z "$BRANCH" ]; then
  : | _sc_write "$CACHE"
  exit 0
fi

REMOTE_URL="$(git config remote.origin.url 2>/dev/null || true)"
if ! parse_remote "$REMOTE_URL"; then
  : | _sc_write "$CACHE"
  exit 0
fi

RESET="#[fg=${THEME[foreground]},bg=${THEME[background]},nobold,noitalics,nounderscore,nodim]"
PROVIDER_ICON=""

PR_COUNT=0
REVIEW_COUNT=0
ISSUE_COUNT=0
BUG_COUNT=0

PR_STATUS=""
REVIEW_STATUS=""
ISSUE_STATUS=""
BUG_STATUS=""

if [ "$PROVIDER" = "github" ]; then
  command -v gh >/dev/null 2>&1 || _sc_keep_or_blank
  command -v jq >/dev/null 2>&1 || _sc_keep_or_blank
  export GH_PROMPT_DISABLED=1

  # When talking to GitHub Enterprise, every `gh` call must be pinned to
  # the right host. The public github.com case is a no-op for --hostname.
  GH_HOST_ARGS=()
  if [ "$HOST" != "github.com" ]; then
    GH_HOST_ARGS=(--hostname "$HOST")
  fi

  PROVIDER_ICON="$RESET#[fg=${THEME[foreground]}] "
  PR_COUNT="$(_timeout_cmd gh "${GH_HOST_ARGS[@]}" pr list --repo "$OWNER_REPO" --json number --jq 'length' 2>/dev/null)" || _sc_keep_or_blank
  REVIEW_COUNT="$(_timeout_cmd gh "${GH_HOST_ARGS[@]}" pr status --repo "$OWNER_REPO" --json reviewRequests --jq '.needsReview | length' 2>/dev/null)" || _sc_keep_or_blank

  SHOW_ASSIGNED="$(tmux show-option -gqv @tokyo-night-tmux_assigned_issues_only 2>/dev/null || true)"
  if [ "$SHOW_ASSIGNED" = "1" ]; then
    LOGIN="$(_timeout_cmd gh "${GH_HOST_ARGS[@]}" api user -q .login 2>/dev/null)" || _sc_keep_or_blank
    QUERY="assignee=$LOGIN&state=open&per_page=100"
  else
    QUERY="state=open&per_page=100"
  fi

  RES="$(_timeout_cmd gh "${GH_HOST_ARGS[@]}" api "repos/$OWNER_REPO/issues?$QUERY" 2>/dev/null | jq '[.[] | select(.pull_request == null) | {labels, type}]' 2>/dev/null)" || _sc_keep_or_blank
  ISSUE_COUNT="$(printf '%s' "$RES" | jq 'length' 2>/dev/null)" || _sc_keep_or_blank
  BUG_COUNT="$(printf '%s' "$RES" | jq 'map(select((.labels | map(.name) | contains(["bug"])) or .type.name == "Bug")) | length' 2>/dev/null)" || _sc_keep_or_blank
  ISSUE_COUNT="$(( ${ISSUE_COUNT:-0} - ${BUG_COUNT:-0} ))"
elif [ "$PROVIDER" = "gitlab" ]; then
  command -v glab >/dev/null 2>&1 || _sc_keep_or_blank
  PROVIDER_ICON="$RESET#[fg=#fc6d26] "
  PR_COUNT="$(_timeout_cmd glab mr list 2>/dev/null | grep -cE '^!' || true)"
  REVIEW_COUNT="$(_timeout_cmd glab mr list --reviewer=@me 2>/dev/null | grep -cE '^!' || true)"
  ISSUE_COUNT="$(_timeout_cmd glab issue list 2>/dev/null | grep -cE '^#' || true)"
else
  : | _sc_write "$CACHE"
  exit 0
fi

PR_COUNT="${PR_COUNT:-0}"
REVIEW_COUNT="${REVIEW_COUNT:-0}"
ISSUE_COUNT="${ISSUE_COUNT:-0}"
BUG_COUNT="${BUG_COUNT:-0}"

if [[ $PR_COUNT -gt 0 ]] 2>/dev/null; then
  PR_STATUS="#[fg=${THEME[ghgreen]},bg=${THEME[background]},bold] ${RESET}${PR_COUNT} "
fi

if [[ $REVIEW_COUNT -gt 0 ]] 2>/dev/null; then
  REVIEW_STATUS="#[fg=${THEME[ghyellow]},bg=${THEME[background]},bold] ${RESET}${REVIEW_COUNT} "
fi

if [[ $ISSUE_COUNT -gt 0 ]] 2>/dev/null; then
  ISSUE_STATUS="#[fg=${THEME[ghgreen]},bg=${THEME[background]},bold] ${RESET}${ISSUE_COUNT} "
fi

if [[ $BUG_COUNT -gt 0 ]] 2>/dev/null; then
  BUG_STATUS="#[fg=${THEME[ghred]},bg=${THEME[background]},bold] ${RESET}${BUG_COUNT} "
fi

printf '%s' "#[fg=${THEME[black]},bg=${THEME[background]},bold] $RESET$PROVIDER_ICON $RESET$PR_STATUS$REVIEW_STATUS$ISSUE_STATUS$BUG_STATUS" | _sc_write "$CACHE"
