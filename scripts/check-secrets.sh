#!/usr/bin/env bash
# check-secrets.sh — no credential in anything a clone exposes (#87).
#
# The history becomes public with the repository, and a clone carries more than
# HEAD: every revision's blobs, plus objects that `git rev-list --all` never
# reaches (a `git add` that was later reset leaves a dangling blob). A pattern
# scan over the tip is not this check.
#
# gitleaks runs from a pinned image, so the rules and the version are a property
# of the tree rather than of the machine running it.
#
# Usage:
#   bash scripts/check-secrets.sh                # history + dangling objects
#   bash scripts/check-secrets.sh --self-test    # prove the scan can fail
#
# Exit: 0 = clean; 1 = a finding (commit/rule named); 2 = docker unavailable.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Pinned: a scan that changes rules when the image moves cannot be quoted in a
# report a month later.
GITLEAKS_IMAGE="${GITLEAKS_IMAGE:-zricethezav/gitleaks:v8.30.1}"

have_docker() { command -v docker >/dev/null 2>&1; }

leak_scan() {
  local dir="$1" extra=("${@:2}")
  docker run --rm -v "$dir:/repo" "$GITLEAKS_IMAGE" \
    detect --source=/repo --no-banner --redact --verbose "${extra[@]}" 2>&1
}

self_test() {
  if ! have_docker; then
    echo "⏭ self-test needs docker (the scan runs from a pinned image)"
    return 2
  fi
  local tmp
  # Two adjacent quoted strings: the source has no contiguous `AKIA` + 16 chars,
  # the shell concatenates them into the full shape at run time. (A scanner that
  # flags this file for a literal would be right — this is how it stays clean.)
  local planted="AKIA""QWERTYUIOPASDFGH"
  tmp="$(mktemp -d)"
  (
    cd "$tmp"
    git init -q .
    git config user.email selftest@example.com
    git config user.name selftest
    # A fake AWS key id: the shape of gitleaks' aws-access-token rule. Not the
    # documentation example (GITLEAKS allowlists that string), so a pass here
    # means the rule fired rather than the allowlist.
    printf 'aws_access_key_id = %s\n' "$planted" > planted.txt
    git add planted.txt
    git commit -q -m "planted"
  ) >/dev/null
  local out
  if out="$(leak_scan "$tmp" --log-opts="--all")"; then
    echo "❌ self-test: a planted credential was not detected — the scan is inert"
    return 1
  fi
  # A failure is not a detection: the rule must be named, and the value must not
  # be echoed into a log that outlives the report.
  if ! printf '%s' "$out" | grep -q "aws-access-token"; then
    echo "❌ self-test: refused, but not by the rule — the reason is not a detection:"
    printf '%s\n' "$out" | head -5
    return 1
  fi
  if printf '%s' "$out" | grep -q "$planted"; then
    echo "❌ self-test: the scan echoed the credential instead of redacting it"
    return 1
  fi
  if ! printf '%s' "$out" | grep -q "Commit:"; then
    echo "❌ self-test: the finding does not name the commit"
    return 1
  fi
  # Second path: an object no ref reaches. Write a blob, never commit it.
  local dangling
  dangling="$(mktemp -d)"
  (
    cd "$dangling"
    git init -q .
    printf 'aws_access_key_id = %s\n' "$planted" |
      git hash-object -w --stdin >/dev/null
    git fsck --lost-found >/dev/null 2>&1 || true
  ) >/dev/null
  if scan_dangling "$dangling" >/dev/null 2>&1; then
    echo "❌ self-test: a planted dangling blob was not detected"
    return 1
  fi
  echo "✅ secret-scan self-test: history rule fires and redacts; a dangling blob is found too"
  return 0
}

# scan_dangling <repo-root> — objects no ref reaches. `git fsck --lost-found`
# writes them to .git/lost-found/{commit,blob,...}; a deleted-but-staged secret
# lives here and survives a clone only as an unreferenced object.
scan_dangling() {
  local repo="$1" lost="$1/.git/lost-found"
  if [ ! -d "$lost" ]; then
    echo "✅ dangling objects: none (git fsck --lost-found writes nothing to scan)"
    return 0
  fi
  local dangling_dir
  dangling_dir="$(mktemp -d)"
  find "$lost" -type f -exec cp {} "$dangling_dir/" \; 2>/dev/null || true
  if [ -z "$(ls -A "$dangling_dir" 2>/dev/null)" ]; then
    echo "✅ dangling objects: none"
    return 0
  fi
  if docker run --rm -v "$dangling_dir:/repo" "$GITLEAKS_IMAGE" \
    dir /repo --no-banner --redact --verbose; then
    echo "✅ dangling objects: no credential found"
    return 0
  fi
  echo "❌ a credential is in an object no ref reaches"
  return 1
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if ! have_docker; then
  echo "⏭ secret scan needs docker (${GITLEAKS_IMAGE}); not a pass without it" >&2
  exit 2
fi

status=0

echo "▶ history: every revision reachable from any ref"
# --all is the default log-opts in recent gitleaks, but the flag is the claim.
if ! leak_scan "$ROOT" --log-opts="--all"; then
  echo "❌ a credential is in the history — rotate it first, then decide about the history"
  status=1
else
  echo "✅ history: no credential found across all refs"
fi

echo "▶ dangling objects: what no ref reaches"
git fsck --lost-found >/dev/null 2>&1 || true
if ! scan_dangling "$ROOT"; then
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "✅ secret scan: clean (history + dangling objects, ${GITLEAKS_IMAGE})"
fi
exit "$status"