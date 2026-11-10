#!/usr/bin/env bash
# check-spdx.sh — the SPDX identifier is on the file a reader opens first (#90).
#
# #83 claimed "SPDX on every published entry point". Two published channels had
# none: 0 of 26 Go files and 0 of 12 Java main sources. Both are distributed as
# source (a Go module is consumed by path; the Java jar's sources are on Central),
# so the source file is the distributor.
#
# The set is fixed here rather than discovered: a guard that infers its own
# subject can shrink with a refactor and still pass.
#
# Usage: bash scripts/check-spdx.sh [--self-test]
# Exit: 0 = every listed file carries the identifier; 1 = one does not (named).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

EXPECTED='SPDX-License-Identifier: Apache-2.0'

# Every file the packaging for these channels includes.
go_files() { git ls-files 'go/*.go' 'go/**/*.go'; }
java_files() { git ls-files 'java/src/main/java/**/*.java'; }
# The entry points the earlier claim did cover, kept so it cannot regress.
entry_points() {
  printf '%s\n' \
    rust/rigorix-schemas/src/lib.rs \
    rust/rigorix-verifier/src/lib.rs \
    rust/rigorix-client/src/lib.rs \
    python/rigorix_verifier/__init__.py \
    typescript/src/index.ts \
    typescript-client/src/index.ts
}

has_spdx() {
  # First two lines only: a header copied into the middle of a file is not a
  # header, and Apache-2.0 §4 retention is about the notice a copier sees.
  head -2 "$1" | grep -qF "$EXPECTED"
}

self_test() {
  local failed=0 sample stripped
  sample="$(go_files | head -1)"
  [ -n "$sample" ] || { echo "self-test: no Go files found"; return 1; }
  if ! has_spdx "$sample"; then
    echo "self-test: the guard rejects an intact file ($sample)"
    failed=1
  fi
  stripped="$(mktemp)"
  tail -n +3 "$sample" >"$stripped"
  if has_spdx "$stripped"; then
    echo "self-test: the guard accepts a header-less file — it cannot refuse"
    failed=1
  fi
  rm -f "$stripped"
  if [ "$failed" -ne 0 ]; then
    echo "❌ SPDX self-test failed — the guard cannot be trusted"
    return 1
  fi
  echo "✅ SPDX self-test: accepts an intact file, refuses one with the header removed"
  return 0
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

status=0
total=0
for file in $(go_files) $(java_files) $(entry_points); do
  [ -f "$file" ] || continue
  total=$(( total + 1 ))
  if ! has_spdx "$file"; then
    echo "❌ $file has no first-two-line '$EXPECTED'"
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  printf '✅ SPDX: %d file(s) carry %s (%d Go, %d Java main, 6 other entry points)\n' \
    "$total" "$EXPECTED" "$(go_files | wc -l | tr -d ' ')" "$(java_files | wc -l | tr -d ' ')"
fi
exit "$status"