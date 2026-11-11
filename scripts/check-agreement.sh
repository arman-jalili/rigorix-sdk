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
# The allow-list keys on the exact line (normalised), not on the file (#101). Keyed
# on the file it accepted *any* sentence in that file that mentioned the old
# agreement — including a new requirement appended to CONTRIBUTING.md, which is the
# file most likely to be edited when the agreement changes. Re-wording an
# allow-listed line is therefore a deliberate edit to the list below, and a run
# with nothing to read is not a pass: it is a refusal (#92's rule).
#
# Usage:
#   bash scripts/check-agreement.sh              # scan the tracked tree
#   bash scripts/check-agreement.sh --list       # also print allow-listed lines
#   bash scripts/check-agreement.sh --self-test  # prove it fails when wrong
#
# Exit: 0 = only the canonical agreement is named (allow-listed lines excepted);
#       1 = a document names a different agreement or an unsupported signing
#           mechanism; 2 = no subject (nothing read, or nothing allow-listed),
#           or a usage/environment problem.
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

# file|normalised line|reason — each entry is one sentence that names the agreement
# this repository *replaced*, kept because the record is the point. The line must
# match exactly (whitespace normalised): a new claim in the same file does not
# inherit the allowance.
ALLOW=(
  "CONTRIBUTING.md|### Why a CLA and not a \`Signed-off-by\` trailer|the heading of the section that explains why a trailer was not sufficient"
  "CONTRIBUTING.md|The project previously used a DCO sign-off. A sign-off records that you had the|the opening of that explanation: what a trailer does and does not grant"
  "CONTRIBUTING.md|to preserve. Version 1.0 of the CLA is the replacement, and the DCO check is gone|states that the replacement removed the check, which a reader must be able to see"
  "docs/CLA.md|**Why a licence agreement and not a sign-off.** A \`Signed-off-by\` trailer records|the agreement's own preamble, stating why a sign-off was not enough"
  "docs/CLA.md|that You had the right to submit the work (the Developer Certificate of Origin).|same preamble: the mechanism it replaced, named so the reason is legible"
  "docs/publication-readiness.md|- The DCO range check states its subject count; zero commits prints|the history of the removed check, and the rule this guard inherited from it"
  "docs/publication-readiness.md|**Decision: a Contributor Licence Agreement, not a DCO sign-off.** Version 1.0 is|the #84 decision record: what was decided, in the words it was decided in"
  "docs/publication-readiness.md|which a \`Signed-off-by\` trailer cannot grant. The DCO check is removed with it|the reason for the decision, which names the mechanism it rejected"
  "docs/publication-readiness.md|(\`scripts/check-dco.sh\` deleted, the \`dco\` job removed, the runner step removed),|the wiring that was removed, so a reader can confirm it is gone"
  "docs/publication-readiness.md|\`CONTRIBUTING.md\`, the DCO removed, the checklist item replaced). The|the acceptance status of that decision"
)

normalise() {
  # Collapse runs of whitespace and trim: a re-wrapped paragraph is the same
  # sentence, a different sentence is not.
  printf '%s' "$1" | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//'
}

allow_reason() {
  local file="$1" line="$2" wanted entry rest stored reason
  wanted="$(normalise "$line")"
  # Cheap rejection first: the stored text is compared after whitespace normalising,
  # so a line that does not even contain its words cannot match.
  for entry in "${ALLOW[@]}"; do
    case "$entry" in "$file|"*) ;; *) continue ;; esac
    rest="${entry#*|}"
    stored="${rest%|*}"
    reason="${rest##*|}"
    if [ "$wanted" = "$stored" ]; then
      printf '%s' "$reason"
      return 0
    fi
  done
  return 1
}

scan() {
  local root="${1:-$ROOT}" name failures=0 allowed=0 read_files=0 file line lineno reason files
  name="$(canonical)" || { echo "check-agreement: docs/CLA.md has no '# ' heading" >&2; exit 2; }

  # The list is the repository's (so a copy without .git still has a subject);
  # the bytes read are the root's.
  files="$(cd "$ROOT" && git ls-files '*.md')" || exit 2
  cd "$root" || exit 2
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    read_files=$((read_files + 1))
    # One pass per file, not one `grep` per line: the per-line form forked twice for
    # every line of every Markdown file (161 files, 20 485 lines), which took 56 s for
    # a scan and 20 minutes for the self-test — the guard was the slowest thing in the
    # gate. Only matching lines are considered, which is what the loop body wanted.
    while IFS=: read -r lineno line; do
      if reason="$(allow_reason "$file" "$line")"; then
        allowed=$((allowed + 1))
        [ "$LIST" -eq 1 ] && printf '  allow-listed %s:%d — %s\n' "$file" "$lineno" "$reason"
        continue
      fi
      printf '❌ %s:%d: names a contribution agreement that CONTRIBUTING.md does not\n' "$file" "$lineno"
      printf '     %s\n' "$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-120)"
      failures=$((failures + 1))
    done < <(grep -niE -- "$PATTERN" "$file" 2>/dev/null)
  done < <(printf '%s\n' "$files")

  if [ "$failures" -gt 0 ]; then
    printf '❌ %d line(s) name an agreement this repository does not use (canonical: %s)\n' \
      "$failures" "$name"
    return 1
  fi
  # No subject is not a pass (#92). Two ways to have none: nothing was read, or
  # nothing allow-listed was found — the latter means the allow-list and the tree
  # have parted company, which is a reason to look, not a verdict.
  if [ "$read_files" -eq 0 ]; then
    printf '❌ agreement: no subject, not evidence — 0 file(s) read under %s\n' "$root" >&2
    return 2
  fi
  if [ "$allowed" -eq 0 ]; then
    printf '❌ agreement: no subject, not evidence — %d file(s) read, none of the %d allow-listed line(s) found\n' \
      "$read_files" "${#ALLOW[@]}" >&2
    return 2
  fi
  printf '✅ agreement: %d line(s) mention the replaced agreement, each allow-listed by line; no other document names one\n' \
    "$allowed"
  return 0
}

fixture() {
  # A copy of the tracked Markdown, so a plant never touches the real tree.
  local tmp="$1"
  ( cd "$ROOT" && git ls-files '*.md' | while IFS= read -r f; do
      mkdir -p "$tmp/$(dirname "$f")"
      cp "$f" "$tmp/$f"
    done )
}

self_test() {
  local name failures=0 tmp out expected count
  name="$(canonical)" || { echo "check-agreement: docs/CLA.md has no '# ' heading" >&2; exit 2; }
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp' >/dev/null 2>&1 || true" EXIT

  # 1. The clean copy passes AND read something: the count is parsed, not matched.
  fixture "$tmp/clean"
  if out="$(scan "$tmp/clean" 2>&1)"; then
    count="$(printf '%s\n' "$out" | sed -n 's/^✅ agreement: \([0-9][0-9]*\) line(s).*/\1/p')"
    if [ -z "$count" ]; then
      echo "❌ self-test: the pass printed no count to parse"; failures=$((failures + 1))
    elif [ "$count" -le 0 ]; then
      echo "❌ self-test: the clean copy passed with a count of $count — a vacuous pass"
      failures=$((failures + 1))
    fi
  else
    echo "❌ self-test: the clean copy failed — the guard rejects correct text"; failures=$((failures + 1))
    printf '%s\n' "$out" | tail -3
  fi

  # 2. A DCO claim in README fails, naming the file and line and the reason.
  fixture "$tmp/readme"
  printf '\n- **Contributing:** DCO sign-off, as before.\n' >>"$tmp/readme/README.md"
  expected="README.md:$(wc -l <"$tmp/readme/README.md" | tr -d ' ')"
  if out="$(scan "$tmp/readme" 2>&1)"; then
    echo "❌ self-test: a planted 'DCO sign-off' in README.md was accepted"; failures=$((failures + 1))
  else
    case "$out" in *"$expected"*) : ;;
      *) echo "❌ self-test: failed, but did not name $expected"; failures=$((failures + 1)) ;; esac
    case "$out" in *"names a contribution agreement that CONTRIBUTING.md does not"*) : ;;
      *) echo "❌ self-test: failed without stating why"; failures=$((failures + 1)) ;; esac
  fi

  # 3. A *new* DCO requirement appended to CONTRIBUTING fails. This is the case the
  #    file-keyed allow-list accepted (#101).
  fixture "$tmp/contributing"
  printf '\nEvery commit must carry the DCO sign-off before it can be merged.\n' >>"$tmp/contributing/CONTRIBUTING.md"
  expected="CONTRIBUTING.md:$(wc -l <"$tmp/contributing/CONTRIBUTING.md" | tr -d ' ')"
  if out="$(scan "$tmp/contributing" 2>&1)"; then
    echo "❌ self-test: a new DCO requirement in CONTRIBUTING.md was allow-listed"; failures=$((failures + 1))
  else
    case "$out" in *"$expected"*) : ;;
      *) echo "❌ self-test: the CONTRIBUTING plant was not named ($expected)"; failures=$((failures + 1)) ;; esac
  fi

  # 4. An empty root is a refusal, not a pass.
  mkdir -p "$tmp/empty"
  if out="$(scan "$tmp/empty" 2>&1)"; then
    echo "❌ self-test: an empty root was accepted"; failures=$((failures + 1))
  else
    status=$?
    case "$out" in *"no subject, not evidence"*) : ;;
      *) echo "❌ self-test: the empty root failed without the reason"; failures=$((failures + 1)) ;; esac
    [ "$status" -eq 2 ] || { echo "❌ self-test: the empty root exited $status, not 2"; failures=$((failures + 1)); }
  fi

  # 5. The canonical name in the same place passes — the guard checks the fact.
  fixture "$tmp/canonical"
  printf '\n- **Contributing:** under the Contributor Licence Agreement.\n' >>"$tmp/canonical/README.md"
  if out="$(scan "$tmp/canonical" 2>&1)"; then :; else
    echo "❌ self-test: the canonical agreement was rejected in README.md"; failures=$((failures + 1))
    printf '%s\n' "$out" | tail -3
  fi

  if [ "$failures" -gt 0 ]; then
    echo "❌ check-agreement self-test: $failures case(s) wrong"
    return 1
  fi
  echo "✅ check-agreement self-test: a new claim fails by line (README, CONTRIBUTING), an empty root exits 2, the canonical name passes"
  return 0
}

if [ "$SELF_TEST" -eq 1 ]; then
  self_test
  exit $?
fi

scan "$SCAN_ROOT"