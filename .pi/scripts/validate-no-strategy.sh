#!/usr/bin/env bash
# validate-no-strategy.sh — a published document is not a strategy memo (#88).
#
# This repository is public. The commercial plan, the competitive framing and an
# assessment of another product's defects do not belong in it; the *contract*
# reasoning they motivated does. A guard, because the reminder had a half-life of
# one release: the sweep that removed the names left the reasoning behind.
#
# Two scans:
#   1. commercial vocabulary in any tracked text file;
#   2. the stem `strateg` in prose (README, docs/**), except ADRs, which record
#      architecture decisions and legitimately discuss strategy.
#
# Usage: bash .pi/scripts/validate-no-strategy.sh [--self-test]
# Exit: 0 = clean; 1 = a hit (file, line, word), or the self-test failed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# Allowlist: path prefix | reason. Every entry is a decision, not a shortcut.
# The agent skills are harness content that never ships as product prose.
ALLOW=(
  ".pi/skills/|agent-harness reference text, not product documentation"
  ".pi/scripts/|the guard's own pattern is not prose"
  "scripts/tracker-sweep.sh|a scanner's pattern, not prose (see the file's comment)"
)

COMMERCIAL_RE='funnel|go-to-market|\bGTM\b|pricing|competitor|\bcustomer\b|\bdeal\b|\bsales\b'
STRATEGY_RE='strateg'

allowlisted() {
  local path="$1" entry prefix
  for entry in "${ALLOW[@]}"; do
    prefix="${entry%%|*}"
    case "$path" in
      "$prefix"*) return 0 ;;
    esac
  done
  return 1
}

# scan <regex> <pathspec...> — prints hits, returns 1 when any is unallowlisted.
scan() {
  local regex="$1"; shift
  local hits=0 line path
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path="${line%%:*}"
    if allowlisted "$path"; then
      continue
    fi
    printf '  %s\n' "$line"
    hits=$(( hits + 1 ))
  done < <(git grep -nIiE "$regex" -- "$@" 2>/dev/null)
  [ "$hits" -eq 0 ]
}

self_test() {
  local failed=0
  local planted="our funnel converts trials into deals"
  local clean="the verifier accepts the frozen envelope shape"

  if ! printf '%s\n' "$planted" | grep -qiE "$COMMERCIAL_RE"; then
    echo "self-test: a planted commercial line was not matched"; failed=1
  fi
  if printf '%s\n' "$clean" | grep -qiE "$COMMERCIAL_RE"; then
    echo "self-test: a clean line was matched"; failed=1
  fi
  if ! printf '%s\n' "the strategic role of this layer" | grep -qiE "$STRATEGY_RE"; then
    echo "self-test: a planted strategy line was not matched"; failed=1
  fi
  if [ "$failed" -ne 0 ]; then
    echo "❌ no-strategy self-test failed — the guard cannot be trusted"
    return 1
  fi
  echo "✅ no-strategy self-test: catches a planted line in both scans, ignores clean prose"
  return 0
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

status=0

# 1. Commercial vocabulary anywhere a reader lands.
if ! scan "$COMMERCIAL_RE" .; then
  echo "❌ commercial vocabulary in a published file (allowlist: .pi/skills, .pi/scripts)"
  status=1
fi

# 2. The strategy stem in prose. ADRs are the exception: they are the place a
#    technical choice is argued, and "strategic" can be a property of a design.
if ! scan "$STRATEGY_RE" "README.md" "docs/**/*.md" ":!docs/adr/**"; then
  echo "❌ 'strateg*' in published prose (ADRs excepted): say what the design does"
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "✅ no commercial-strategy vocabulary in published files"
fi
exit "$status"