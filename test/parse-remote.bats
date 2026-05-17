#!/usr/bin/env bats
#
# Unit tests for parse_remote (lib/parse-remote.sh).
#
# Covers SSH / HTTPS / http / ssh:// URL shapes for the public hosts, plus
# the GitHub Enterprise detection path. _pr_host_auth is replaced with a
# test double so we never invoke a real `gh` / `glab`.

setup() {
  # shellcheck source=../lib/parse-remote.sh
  source "${BATS_TEST_DIRNAME}/../lib/parse-remote.sh"

  # Default test double: claim authentication only for hosts listed in
  # $STUB_AUTH_GH or $STUB_AUTH_GLAB (space-separated). Override per test.
  _pr_host_auth() {
    local provider="$1" host="$2" allowed=""
    case "$provider" in
      github) allowed=" ${STUB_AUTH_GH:-} " ;;
      gitlab) allowed=" ${STUB_AUTH_GLAB:-} " ;;
      *) return 1 ;;
    esac
    [[ "$allowed" == *" $host "* ]]
  }
}

# parse_remote exports PROVIDER/HOST/OWNER_REPO into its caller's scope.
# Bats's `run` swallows those (it forks a subshell), so we invoke directly
# and capture the exit status manually.
try_parse() {
  PROVIDER=""; HOST=""; OWNER_REPO=""
  status=0
  parse_remote "$1" || status=$?
}

# ---------- github.com ----------

@test "parses git@github.com SSH URLs" {
  try_parse "git@github.com:owner/repo.git"
  [ "$status" -eq 0 ]
  [ "$PROVIDER" = "github" ]
  [ "$HOST" = "github.com" ]
  [ "$OWNER_REPO" = "owner/repo" ]
}

@test "parses ssh://git@github.com URLs" {
  try_parse "ssh://git@github.com/owner/repo.git"
  [ "$status" -eq 0 ]
  [ "$PROVIDER" = "github" ]
  [ "$HOST" = "github.com" ]
  [ "$OWNER_REPO" = "owner/repo" ]
}

@test "parses https://github.com URLs without .git suffix" {
  try_parse "https://github.com/owner/repo"
  [ "$status" -eq 0 ]
  [ "$PROVIDER" = "github" ]
  [ "$HOST" = "github.com" ]
  [ "$OWNER_REPO" = "owner/repo" ]
}

@test "parses https URLs with embedded credentials" {
  try_parse "https://user:token@github.com/owner/repo.git"
  [ "$status" -eq 0 ]
  [ "$PROVIDER" = "github" ]
  [ "$HOST" = "github.com" ]
  [ "$OWNER_REPO" = "owner/repo" ]
}

@test "is case-insensitive on hostname" {
  try_parse "https://GitHub.COM/owner/repo.git"
  [ "$status" -eq 0 ]
  [ "$HOST" = "github.com" ]
}

# ---------- gitlab.com ----------

@test "parses git@gitlab.com SSH URLs" {
  try_parse "git@gitlab.com:group/project.git"
  [ "$status" -eq 0 ]
  [ "$PROVIDER" = "gitlab" ]
  [ "$HOST" = "gitlab.com" ]
  [ "$OWNER_REPO" = "group/project" ]
}

@test "parses gitlab subgroup paths" {
  try_parse "https://gitlab.com/group/subgroup/project.git"
  [ "$status" -eq 0 ]
  [ "$PROVIDER" = "gitlab" ]
  [ "$OWNER_REPO" = "group/subgroup/project" ]
}

# ---------- GitHub Enterprise (auth-probed) ----------

@test "detects GHE host when gh is authenticated to it" {
  STUB_AUTH_GH="git.acme.com"
  try_parse "git@git.acme.com:team/service.git"
  [ "$status" -eq 0 ]
  [ "$PROVIDER" = "github" ]
  [ "$HOST" = "git.acme.com" ]
  [ "$OWNER_REPO" = "team/service" ]
}

@test "detects GHE host via https URL" {
  STUB_AUTH_GH="ghe.example.io"
  try_parse "https://ghe.example.io/org/repo.git"
  [ "$status" -eq 0 ]
  [ "$PROVIDER" = "github" ]
  [ "$HOST" = "ghe.example.io" ]
  [ "$OWNER_REPO" = "org/repo" ]
}

@test "detects self-hosted GitLab when glab is authenticated to it" {
  STUB_AUTH_GLAB="gitlab.acme.com"
  try_parse "git@gitlab.acme.com:group/project.git"
  [ "$status" -eq 0 ]
  [ "$PROVIDER" = "gitlab" ]
  [ "$HOST" = "gitlab.acme.com" ]
  [ "$OWNER_REPO" = "group/project" ]
}

@test "prefers gh over glab when both are authenticated to the same host" {
  STUB_AUTH_GH="hybrid.acme.com"
  STUB_AUTH_GLAB="hybrid.acme.com"
  try_parse "git@hybrid.acme.com:org/repo.git"
  [ "$status" -eq 0 ]
  [ "$PROVIDER" = "github" ]
}

# ---------- failure modes ----------

@test "rejects unknown unauthenticated hosts" {
  try_parse "git@some-private.example.com:org/repo.git"
  [ "$status" -ne 0 ]
}

@test "rejects empty remote URL" {
  try_parse ""
  [ "$status" -ne 0 ]
}

@test "rejects malformed URL with no path" {
  try_parse "git@github.com:"
  [ "$status" -ne 0 ]
}

@test "rejects unsupported scheme" {
  try_parse "file:///srv/git/repo.git"
  [ "$status" -ne 0 ]
}
