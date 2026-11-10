#!/usr/bin/env bash
# check-dco.sh — every commit in a range carries a Developer Certificate of
# Origin sign-off (DCO 1.1). The policy lives in CONTRIBUTING.md; this is the
# part that does not depend on anyone remembering it.
#
# Usage:
#   bash scripts/check-dco.sh                     # origin/main..HEAD, or HEAD~1..HEAD
#   bash scripts/check-dco.sh <range>             # e.g. origin/main..HEAD
#   bash scripts/check-dco.sh --self-test         # prove the check can refuse
#
# Exit: 0 = every commit signed off (or none to check); 1 = a commit is missing
# the trailer (named), or the self-test failed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# The trailer, at the start of a line: name and an email in angle brackets.
# Case-insensitive on the tag because tools differ; the value must be present.
has_signoff() {
  printf '%s\n' "$1" | grep -qiE '^Signed-off-by: .+ <[^<>]+@[^<>]+>[[:space:]]*$'
}

self_test() {
  local failed=0
  local with='fix(x): y

Signed-off-by: A Contributor <a@example.com>'
  local without='fix(x): y

No trailer here.'
  local malformed='fix(x): y

Signed-off-by: A Contributor'

  if ! has_signoff "$with"; then
    echo "self-test: a valid sign-off was rejected"; failed=1
  fi
  if has_signoff "$without"; then
    echo "self-test: a commit without a sign-off was accepted"; failed=1
  fi
  if has_signoff "$malformed"; then
    echo "self-test: a sign-off without an email was accepted"; failed=1
  fi

  if [ "$failed" -ne 0 ]; then
    echo "❌ DCO self-test failed — the check cannot be trusted"
    return 1
  fi
  echo "✅ DCO self-test: accepts a trailer, refuses a missing or malformed one"
  return 0
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

RANGE="${1:-}"
if [ -z "$RANGE" ]; then
  if git rev-parse --verify --quiet origin/main >/dev/null; then
    RANGE="origin/main..HEAD"
  else
    RANGE="HEAD~1..HEAD"
  fi
fi

# One `git log` per commit: the range is a pull request, not a release, so the
# cost is nil and the parsing stays readable on bash 3.2 (macOS), which cannot
# carry a NUL through a parameter expansion.
missing=0
checked=0
for hash in $(git rev-list "$RANGE" 2>/dev/null); do
  checked=$(( checked + 1 ))
  body="$(git log -1 --format=%B "$hash")"
  if ! has_signoff "$body"; then
    subject="$(printf '%s\n' "$body" | head -1)"
    echo "❌ $(printf '%.10s' "$hash") — no Signed-off-by trailer: $subject"
    missing=$(( missing + 1 ))
  fi
done

if [ "$checked" -eq 0 ]; then
  # A check that passes with nothing to examine is not a pass: say what it
  # examined, so nobody reads the ✅ as evidence. `--self-test` is the evidence.
  echo "⏭ DCO: 0 commits in $RANGE — no subject, not evidence (--self-test covers the predicate)"
  exit 0
fi

if [ "$missing" -ne 0 ]; then
  cat >&2 <<'MSG'

The DCO is a trailer, not a signature in a comment:
    git commit -s -m "…"          (new commit)
    git commit --amend -s         (last commit)
See CONTRIBUTING.md. Commits made before the policy are history and are not
rewritten; this check applies to the range a pull request adds.
MSG
  exit 1
fi

echo "✅ DCO: $checked commit(s) in $RANGE carry Signed-off-by"
exit 0
