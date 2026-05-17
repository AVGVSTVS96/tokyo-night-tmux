#!/usr/bin/env bash
#
# parse_remote inspects a `git config remote.origin.url` value and, if it
# points at a known GitHub- or GitLab-compatible host, exports:
#
#   PROVIDER     "github" | "gitlab"
#   HOST         the hostname (e.g. "github.com" or "git.acme.com")
#   OWNER_REPO   "owner/name" (no trailing ".git")
#
# Returns 0 on success, non-zero on unparseable input or unrecognized host.
#
# Public GitHub.com / GitLab.com are matched directly. Anything else is
# considered a candidate for GitHub Enterprise / self-hosted GitLab and is
# probed via `gh auth status --hostname HOST` (or `glab auth status`). If
# the local CLI is authenticated to that host, we trust it. This avoids
# maintaining a user-managed allowlist while keeping the check zero-cost
# in steady state (it only runs in the cached refresh path, never on
# redraw).

# Test seam: tests override _pr_host_auth to avoid invoking the real CLIs.
# Returns 0 if the user is authenticated to host $2 on provider $1.
_pr_host_auth() {
  local provider="$1" host="$2"
  case "$provider" in
    github) command -v gh   >/dev/null 2>&1 && gh   auth status --hostname "$host" >/dev/null 2>&1 ;;
    gitlab) command -v glab >/dev/null 2>&1 && glab auth status --hostname "$host" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

parse_remote() {
  local url="$1" rest host path

  PROVIDER=""
  HOST=""
  OWNER_REPO=""

  [ -n "$url" ] || return 1
  url="${url%.git}"

  # Normalize the URL into "host" + "path" regardless of scheme.
  case "$url" in
    git@*:*)
      rest="${url#git@}"
      host="${rest%%:*}"
      path="${rest#*:}"
      ;;
    ssh://*)
      rest="${url#ssh://}"
      rest="${rest#*@}"            # strip optional user@
      host="${rest%%/*}"
      host="${host%%:*}"           # strip optional :port
      path="${rest#*/}"
      ;;
    https://*|http://*)
      rest="${url#*://}"
      rest="${rest#*@}"            # strip optional user:pass@
      host="${rest%%/*}"
      host="${host%%:*}"           # strip optional :port
      path="${rest#*/}"
      ;;
    *)
      return 1
      ;;
  esac

  # Lowercase the hostname for case-insensitive matching. `${var,,}` is
  # bash 4+; macOS still ships bash 3.2, so use tr instead.
  host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
  path="${path#/}"
  path="${path%.git}"
  path="${path%/}"
  [ -n "$host" ] && [ -n "$path" ] || return 1

  # Public hosts: match without an auth probe.
  case "$host" in
    github.com) PROVIDER="github"; HOST="$host"; OWNER_REPO="$path"; return 0 ;;
    gitlab.com) PROVIDER="gitlab"; HOST="$host"; OWNER_REPO="$path"; return 0 ;;
  esac

  # Self-hosted: trust whichever CLI the user is already authenticated to.
  if _pr_host_auth github "$host"; then
    PROVIDER="github"; HOST="$host"; OWNER_REPO="$path"; return 0
  fi
  if _pr_host_auth gitlab "$host"; then
    PROVIDER="gitlab"; HOST="$host"; OWNER_REPO="$path"; return 0
  fi

  return 1
}
