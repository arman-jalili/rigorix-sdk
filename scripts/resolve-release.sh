#!/usr/bin/env bash
# resolve-release.sh — what release is this run about, and which channels is it asking?
#
# The answer was written twice in `publish.yml`, byte for byte, in `smoke` and in
# `verify-published` (#127). Three decisions live in it, and each is a place two copies
# can diverge silently: **which tag** (the pushed tag, else the newest `v*`), **which
# channels** (the dispatch input, else the ones this workflow publishes), and **what it
# prints** — the only evidence a reader has of what the run decided.
#
# It is a script rather than a composite action so that it is testable outside Actions:
# every failure this has had was a harness condition, not an artifact.
#
# Usage:
#   bash scripts/resolve-release.sh --event push --ref-name v0.10.0
#   bash scripts/resolve-release.sh --event workflow_dispatch --input-channels ""
#   bash scripts/resolve-release.sh --self-test
#
# Output: two `key=value` lines (`tag=…`, `channels=…`) and one human line. In Actions,
# `--github-output <file>` also appends them to `$GITHUB_OUTPUT`.
#
# Exit: 0 = resolved; 1 = could not resolve (no `v*` tag in the clone); 2 = bad usage.
set -uo pipefail

# The channels this workflow publishes -- one constant, next to the uploads it describes.
# crates is `cargo publish` by hand and Go is served by the tag itself, so neither is in
# it: a default that demanded them would be a red run for steps no job here performs.
PUBLISHED_CHANNELS="pypi,npm,maven"
# The five a *release* has, read from the gate rather than typed again (#134, #126).
ALL_CHANNELS="$(bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-release.sh" --print-channels 2>/dev/null)"
[ -n "$ALL_CHANNELS" ] ||
  { echo "resolve-release: cannot read the channel set from check-release.sh --print-channels" >&2; exit 2; }

# Two questions, two default sets (#134). A run must not be able to pass a partial answer
# to a question it did not narrow:
#   tag push  → "did the channels this workflow uploads take the version?" (crates and Go
#               are manual/self-served, and are settled by a release dispatch)
#   dispatch  → "is the release complete everywhere?" — all five, because that is the
#               question the job's name claims
default_channels() {
  case "$1" in
    push) printf '%s' "$PUBLISHED_CHANNELS" ;;
    *)    printf '%s' "$ALL_CHANNELS" ;;
  esac
}

EVENT=""
REF_NAME=""
INPUT_TAG=""
INPUT_CHANNELS=""
GITHUB_OUTPUT_FILE=""
SELF_TEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --event) EVENT="$2"; shift ;;
    --ref-name) REF_NAME="$2"; shift ;;
    --input-tag) INPUT_TAG="$2"; shift ;;
    --input-channels) INPUT_CHANNELS="$2"; shift ;;
    --github-output) GITHUB_OUTPUT_FILE="$2"; shift ;;
    --self-test) SELF_TEST=1 ;;
    *) echo "resolve-release: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

# A tag-shaped name is `v` followed by a digit: `go/v0.10.0` and `rust-v0.10.0` mark other
# coordinates, and `--ref-name` on a tag push is always the plain one.
newest_tag() {
  local tag
  # `--force`: a dispatch's checkout may be shallow and may already hold a stale tag.
  git fetch --force --tags --quiet origin '+refs/tags/*:refs/tags/*' 2>/dev/null || true
  tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null)"
  printf '%s' "$tag"
}

resolve() {
  local tag channels
  if [ -n "$INPUT_TAG" ]; then
    tag="$INPUT_TAG"
  elif [ "$EVENT" = "push" ] && case "$REF_NAME" in v[0-9]*) true ;; *) false ;; esac; then
    # The pushed tag, not the newest one: `git describe` would answer with a later tag
    # than the run was started for.
    tag="$REF_NAME"
  else
    tag="$(newest_tag)"
    [ -n "$tag" ] ||
      { echo "❌ no v* tag to resolve — pass -f tag=… (a clone with no tags cannot say which release this is)" >&2; return 1; }
  fi
  # The steps after this read the release's own tree (`git show "$tag:path"`), so the
  # tag has to be here. A dispatch's checkout is a branch and has no tags, and a caller
  # that names a tag explicitly is exactly the case that must still work (#129).
  if ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
    git fetch --force --tags --quiet origin '+refs/tags/*:refs/tags/*' 2>/dev/null || true
  fi
  channels="${INPUT_CHANNELS:-$(default_channels "$EVENT")}"
  printf 'tag=%s\n' "$tag"
  printf 'channels=%s\n' "$channels"
  printf 'checking %s (channels: %s)\n' "$tag" "$channels"
  if [ -n "$GITHUB_OUTPUT_FILE" ]; then
    printf 'tag=%s\n' "$tag" >>"$GITHUB_OUTPUT_FILE"
    printf 'channels=%s\n' "$channels" >>"$GITHUB_OUTPUT_FILE"
  fi
}

self_test() {
  local failures=0 cases=0 out
  # Globals: the cases `cd` into a scratch repository, so the script must be called by
  # absolute path (a relative one stops existing after the `cd`), and the trap runs after
  # `self_test` returns, when a local would be unset.
  SELF_TEST_TMP="$(mktemp -d)"
  tmp="$SELF_TEST_TMP"
  trap 'rm -rf "$SELF_TEST_TMP" >/dev/null 2>&1 || true' EXIT

  check() {  # check LABEL WANTED EXPECTED_EXIT [ARGS…]
    local label="$1" wanted="$2" want_rc="$3"; shift 3
    local rc
    cases=$((cases + 1))
    out="$( cd "$tmp/repo" 2>/dev/null && bash "$SELF" "$@" 2>&1 )"
    rc=$?
    if [ "$rc" -ne "$want_rc" ]; then
      echo "❌ self-test [$label]: exit $rc, wanted $want_rc"; failures=$((failures + 1)); return
    fi
    case "$out" in
      *"$wanted"*) : ;;
      *) echo "❌ self-test [$label]: did not answer \"$wanted\""
         printf '%s\n' "$out" | tail -3; failures=$((failures + 1)) ;; esac
  }

  # A clone with tags, and one without: the two states the resolver must tell apart.
  mkdir -p "$tmp/repo"
  git -C "$tmp/repo" init -q
  git -C "$tmp/repo" -c user.email=self@test.invalid -c user.name=selftest commit -q --allow-empty -m one
  git -C "$tmp/repo" -c user.email=self@test.invalid -c user.name=selftest tag -a v0.9.0 -m 0.9.0
  git -C "$tmp/repo" -c user.email=self@test.invalid -c user.name=selftest commit -q --allow-empty -m two
  git -C "$tmp/repo" -c user.email=self@test.invalid -c user.name=selftest tag -a v0.10.0 -m 0.10.0

  check "tag push" "tag=v0.10.0" 0 --event push --ref-name v0.10.0
  check "tag push ignores the newest" "tag=v0.9.0" 0 --event push --ref-name v0.9.0
  check "dispatch input" "tag=v0.9.0" 0 --event workflow_dispatch --input-tag v0.9.0
  # Two default questions (#134): a dispatch that names nothing asks whether the release
  # is complete everywhere; a tag push asks about the channels this workflow uploads.
  check "dispatch default asks all five" "channels=crates,pypi,npm,maven,go" 0 \
    --event workflow_dispatch --input-tag v0.10.0 --input-channels ""
  check "push default asks what this workflow publishes" "channels=pypi,npm,maven" 0 \
    --event push --ref-name v0.10.0 --input-channels ""
  check "dispatch named channels" "channels=pypi,go" 0 \
    --event workflow_dispatch --input-tag v0.10.0 --input-channels pypi,go
  check "dispatch resolves the newest tag" "tag=v0.10.0" 0 --event workflow_dispatch

  # A clone with no tags cannot say which release this is, and must say so rather than
  # answer with an empty tag that every later step would echo.
  # A *fresh* repository: `git init` in the one above would keep its tags.
  mkdir -p "$tmp/norepo"
  git -C "$tmp/norepo" init -q
  cases=$((cases + 1))
  if out="$( cd "$tmp/norepo" && bash "$SELF" --event workflow_dispatch 2>&1 )"; then
    echo "❌ self-test [no tags]: answered instead of refusing"
    failures=$((failures + 1))
  else
    case "$out" in
      *"no v* tag to resolve"*) : ;;
      *) echo "❌ self-test [no tags]: refused without saying what to do"
         printf '%s\n' "$out" | tail -2; failures=$((failures + 1)) ;; esac
  fi

  # A named tag that is not in this clone — a dispatch from a branch, where the caller
  # passed `-f tag=…` — must still resolve, because the next step reads that tag's tree.
  cases=$((cases + 1))
  git -C "$tmp/repo" clone -q --bare "$tmp/repo" "$tmp/origin.git"
  git -C "$tmp/repo" remote add origin "$tmp/origin.git" 2>/dev/null || true
  git -C "$tmp/repo" tag -d v0.9.0 >/dev/null
  if out="$( cd "$tmp/repo" && bash "$SELF" --event workflow_dispatch --input-tag v0.9.0 2>&1 )"; then
    case "$out" in
      *"tag=v0.9.0"*) : ;;
      *) echo "❌ self-test [named tag, not local]: resolved to something else"
         printf '%s\n' "$out" | tail -2; failures=$((failures + 1)) ;; esac
    # And the object the next step reads is now here.
    git -C "$tmp/repo" rev-parse -q --verify refs/tags/v0.9.0 >/dev/null 2>&1 ||
      { echo "❌ self-test [named tag, not local]: the tag object was not fetched, so \`git show\` would fail"; failures=$((failures + 1)); }
  else
    echo "❌ self-test [named tag, not local]: refused a tag it could have fetched"
    printf '%s\n' "$out" | tail -3; failures=$((failures + 1))
  fi

  # The output contract Actions consumes.
  cases=$((cases + 1))
  : >"$tmp/out"
  ( cd "$tmp/repo" && bash "$SELF" --event push --ref-name v0.10.0 --github-output "$tmp/out" >/dev/null 2>&1 ) || true
  if grep -qx 'tag=v0.10.0' "$tmp/out" && grep -qx 'channels=pypi,npm,maven' "$tmp/out"; then :; else
    echo "❌ self-test [github output]: the two keys a step consumes were not written"
    printf '%s\n' "$(cat "$tmp/out")" | tail -3; failures=$((failures + 1))
  fi

  if [ "$failures" -gt 0 ]; then
    echo "❌ resolve-release self-test: $failures of $cases case(s) wrong"
    return 1
  fi
  echo "✅ resolve-release self-test: $cases cases — the pushed tag wins over the newest, a dispatch honours its input, the default is two questions — a push asks the channels this workflow publishes, a dispatch asks all five (read from the gate, not typed again), a named tag missing from the clone is fetched (the next step reads its tree), a clone with no tags refuses by name, and the two output keys are written"
  return 0
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
if [ "$SELF_TEST" -eq 1 ]; then
  self_test
  exit $?
fi

resolve