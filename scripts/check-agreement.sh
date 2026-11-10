#!/usr/bin/env bash
# check-agreement.sh — the contribution agreement a document states must be the
# one the repository uses.
#
# Why this exists: #84 replaced the DCO with a CLA, and its acceptance check was
# `git grep -n 'Developer Certificate of Origin'`. The README says "DCO sign-off",
# so the search passed while the sentence was wrong. A grep for a phrase is not a
# check on a fact.
#
# The canonical answer is not a constant in this script: it is the title of
# docs/CLA.md, the document CONTRIBUTING.md points at. Change the agreement and
# this guard follows; change a document to name a different one and it fails.
#
# Usage:
#   bash scripts/check-agreement.sh              # scan the tracked tree
#   bash scripts/check-agreement.sh --list       # also print allow-listed lines
#   bash scripts/check-agreement.sh --self-test  # prove it fails when wrong
#
# Exit: 0 = only the canonical agreement is named (allow-listed lines excepted);
#       1 = a document names a different agreement or an unsupported signing
#           mechanism; 2 = usage or environment problem.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST=0
SELF_TEST=0
SCAN_ROOT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST=1 ;;
    --self-test) SELF_TEST=1 ;;
    --root) SCAN_ROOT="$2"; shift ;;
    *) echo "check-agreement: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

canonical() {
  # The agreement's name, taken from the document itself.
  local heading
  heading="$(head -1 "$ROOT/docs/CLA.md" 2>/dev/null)"
  case "$heading" in
    "# "*) printf '%s' "${heading#\# }" ;;
    *) return 1 ;;
  esac
}

# Phrases that assert a contribution agreement, or a signing mechanism that is not
# the canonical one. Case-insensitive.
PATTERN='\bDCO\b|Developer Certificate of Origin|Signed-off-by|\bsign[ -]off\b'

# file|extended-regexp|reason — every allow-listed line is a mention of the
# agreement the repository *replaced*, kept because the record is the point.
ALLOW=(
  "CONTRIBUTING.md|DCO|states why the DCO was replaced by the CLA; removing it would hide the reason"
  "CONTRIBUTING.md|Signed-off-by|quotes the trailer it explains was not sufficient"
  "docs/publication-readiness.md|DCO|the #84 decision record, which necessarily names the agreement it replaced"
  "docs/publication-readiness.md|Signed-off-by|same record: what a trailer does and does not grant"
  "docs/CLA.md|Developer Certificate of Origin|the agreement's own preamble, stating why a sign-off was not enough"
  "docs/CLA.md|sign[ -]off|same preamble: the mechanism it replaced, named so the reason is legible"
)

allow_reason() {
  local file="$1" line="$2" entry pattern reason
  for entry in "${ALLOW[@]}"; do
    pattern="${entry#*|}"; pattern="${pattern%|*}"
    reason="${entry##*|}"
    case "$entry" in "$file|"*) ;; *) continue ;; esac
    if printf '%s\n' "$line" | grep -Eiq -- "$pattern"; then
      printf '%s' "$reason"
      return 0
    fi
  done
  return 1
}

scan() {
  local root="${1:-$ROOT}" name failures=0 allowed=0 file line lineno reason
  name="$(canonical)" || { echo "check-agreement: docs/CLA.md has no '# ' heading" >&2; exit 2; }

  # The list is the repository's (so a copy without .git still has a subject);
  # the bytes read are the root's.
  local files
  files="$(cd "$ROOT" && git ls-files '*.md')" || exit 2
  cd "$root" || exit 2
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    lineno=0
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      printf '%s\n' "$line" | grep -Eiq -- "$PATTERN" || continue
      # A line may legitimately name the canonical agreement alongside the old one
      # ("Why a CLA and not a Signed-off-by trailer"); the allow-list decides.
      if reason="$(allow_reason "$file" "$line")"; then
        allowed=$((allowed + 1))
        [ "$LIST" -eq 1 ] && printf '  allow-listed %s:%d — %s\n' "$file" "$lineno" "$reason"
        continue
      fi
      printf '❌ %s:%d: names a contribution agreement that CONTRIBUTING.md does not\n' "$file" "$lineno"
      printf '     %s\n' "$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-120)"
      failures=$((failures + 1))
    done <"$file"
  done < <(printf '%s\n' "$files")

  if [ "$failures" -gt 0 ]; then
    printf '❌ %d line(s) name an agreement this repository does not use (canonical: %s)\n' \
      "$failures" "$name"
    return 1
  fi
  printf '✅ agreement: %d line(s) mention the replaced agreement, each allow-listed; no other document names one\n' \
    "$allowed"
  return 0
}

self_test() {
  local name failures=0 tmp
  name="$(canonical)" || { echo "check-agreement: docs/CLA.md has no '# ' heading" >&2; exit 2; }
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp' >/dev/null 2>&1 || true" EXIT

  # A copy of the tracked Markdown, so the plant never touches the real tree.
  ( cd "$ROOT" && git ls-files '*.md' | while IFS= read -r f; do
      mkdir -p "$tmp/$(dirname "$f")"
      cp "$f" "$tmp/$f"
    done )

  # 1. clean copy passes
  if out="$(LIST=0 scan "$tmp" 2>&1)"; then
    case "$out" in
      *"line(s) mention the replaced agreement"*) : ;;
      *) echo "❌ self-test: the clean copy passed without reading any line — a vacuous pass"
         failures=$((failures + 1)) ;;
    esac
  else
    echo "❌ self-test: the clean copy failed — the guard rejects correct text"; failures=$((failures + 1))
    printf '%s\n' "$out" | tail -3
  fi

  # 2. a DCO claim in README fails, and names the file and line
  printf '\n- **Contributing:** DCO sign-off, as before.\n' >>"$tmp/README.md"
  expected="README.md:$(wc -l <"$tmp/README.md" | tr -d ' ')"
  if out="$(LIST=0 scan "$tmp" 2>&1)"; then
    echo "❌ self-test: a planted 'DCO sign-off' in README.md was accepted"; failures=$((failures + 1))
  else
    case "$out" in
      *"$expected"*) : ;;
      *) echo "❌ self-test: failed, but did not name $expected"; failures=$((failures + 1)) ;;
    esac
    case "$out" in
      *"names a contribution agreement that CONTRIBUTING.md does not"*) : ;;
      *) echo "❌ self-test: failed without stating why"; failures=$((failures + 1)) ;;
    esac
  fi

  # 3. the canonical name in the same place passes — the guard checks the fact,
  #    not the word.
  ( cd "$tmp" && sed -i.bak -e '$d' README.md && rm -f README.md.bak )
  printf '\n- **Contributing:** under the Contributor Licence Agreement.\n' >>"$tmp/README.md"
  if out="$(LIST=0 scan "$tmp" 2>&1)"; then :; else
    echo "❌ self-test: the canonical agreement was rejected in README.md"; failures=$((failures + 1))
    printf '%s\n' "$out" | tail -3
  fi

  if [ "$failures" -gt 0 ]; then
    echo "❌ check-agreement self-test: $failures case(s) wrong"
    return 1
  fi
  echo "✅ check-agreement self-test: plants a DCO claim (fails, names file:line), accepts the canonical name"
  return 0
}

if [ "$SELF_TEST" -eq 1 ]; then
  self_test
  exit $?
fi

scan "$SCAN_ROOT"