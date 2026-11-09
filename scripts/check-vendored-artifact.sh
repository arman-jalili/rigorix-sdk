#!/usr/bin/env bash
# check-vendored-artifact.sh — the two vendored copies are one fact.
#
# `go/gate/testdata/` and `python/rigorix_verifier/_wasm/` each carry the same
# 1.9 MB WASI artifact, and each language records its digest twice (PROVENANCE.md
# and a source constant). Nothing compared them until this guard, so one copy
# could be updated and the other not — two languages running two gates.
#
# Checks, in order, and every failure names the file that drifted:
#   1. both copies exist
#   2. the copies are byte-identical
#   3. both PROVENANCE.md files record the digest and size of their copy
#   4. both source constants (Go `artifactSHA256`, Python `ARTIFACT_SHA256`)
#      record the same digest
#
# Usage: bash scripts/check-vendored-artifact.sh
# Exit: 0 = one fact; 1 = drift (message names the file).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PY_ARTIFACT="python/rigorix_verifier/_wasm/rigorix_gate_wasi.wasm"
GO_ARTIFACT="go/gate/testdata/rigorix_gate_wasi.wasm"
PY_PROVENANCE="python/rigorix_verifier/_wasm/PROVENANCE.md"
GO_PROVENANCE="go/gate/testdata/PROVENANCE.md"
PY_CONSTANT_FILE="python/rigorix_verifier/binding/loader.py"
GO_CONSTANT_FILE="go/gate/artifact.go"
EXPECTED_SIZE=1896910

fail() {
  printf '❌ %s\n' "$1" >&2
  exit 1
}

digest_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

size_of() {
  wc -c <"$1" | tr -d '[:space:]'
}

# The line number is part of the message: the reader has to be able to look.
recorded_digest() {
  local file="$1" line
  line="$(grep -n -E 'sha256:[^0-9a-f]*[0-9a-f]{64}' "$file" | head -1)"
  if [ -z "$line" ]; then
    fail "$file records no 'sha256: <64 hex>' line"
  fi
  printf '%s\n' "$(printf '%s' "${line#*:}" | grep -Eo '[0-9a-f]{64}')"
}

recorded_size() {
  local file="$1" raw
  raw="$(grep -n -E 'size:[^0-9]*[0-9]' "$file" | head -1)"
  if [ -z "$raw" ]; then
    fail "$file records no 'size:' line"
  fi
  printf '%s\n' "$(printf '%s' "${raw#*:}" | grep -Eo '[0-9][0-9,]*' | head -1 | tr -d ',')"
}

recorded_constant() {
  local file="$1" name="$2" line
  line="$(grep -n -E "(^|[^A-Za-z0-9_])$name[[:space:]]*=[[:space:]]*\"[0-9a-f]{64}\"" "$file" | head -1)"
  if [ -z "$line" ]; then
    fail "$file has no \`$name = \"<64 hex>\"\` constant"
  fi
  printf '%s\n' "$(printf '%s' "${line#*:}" | grep -Eo '[0-9a-f]{64}')"
}

# 1. both copies exist.
for copy in "$PY_ARTIFACT" "$GO_ARTIFACT"; do
  [ -f "$ROOT/$copy" ] || fail "missing vendored copy $copy"
done

PY_DIGEST="$(digest_of "$ROOT/$PY_ARTIFACT")"
GO_DIGEST="$(digest_of "$ROOT/$GO_ARTIFACT")"
PY_SIZE="$(size_of "$ROOT/$PY_ARTIFACT")"
GO_SIZE="$(size_of "$ROOT/$GO_ARTIFACT")"

# 2. the copies are byte-identical. Name the file that has to change.
if [ "$PY_DIGEST" != "$GO_DIGEST" ]; then
  fail "the two vendored copies differ: $GO_ARTIFACT is $GO_DIGEST ($GO_SIZE B), but $PY_ARTIFACT is $PY_DIGEST ($PY_SIZE B) — update both from the same build"
fi

# 3. each PROVENANCE.md records its own copy.
for pair in "$PY_PROVENANCE:$PY_DIGEST:$PY_SIZE" "$GO_PROVENANCE:$GO_DIGEST:$GO_SIZE"; do
  provenance="${pair%%:*}"
  rest="${pair#*:}"
  digest="${rest%%:*}"
  size="${rest##*:}"
  recorded_digest_value="$(recorded_digest "$ROOT/$provenance")"
  [ "$recorded_digest_value" = "$digest" ] ||
    fail "$provenance records sha256 $recorded_digest_value, but the copy hashes to $digest — the provenance must change with the artifact"
  recorded_size_value="$(recorded_size "$ROOT/$provenance")"
  [ "$recorded_size_value" = "$size" ] ||
    fail "$provenance records size $recorded_size_value, but the copy is $size bytes"
done

# 4. both source constants agree with the bytes. The loader that refuses a
#    mismatch must refuse over the same digest the other language trusts.
PY_CONSTANT="$(recorded_constant "$ROOT/$PY_CONSTANT_FILE" ARTIFACT_SHA256)"
GO_CONSTANT="$(recorded_constant "$ROOT/$GO_CONSTANT_FILE" artifactSHA256)"
[ "$PY_CONSTANT" = "$PY_DIGEST" ] ||
  fail "$PY_CONSTANT_FILE records $PY_CONSTANT, but the copy hashes to $PY_DIGEST"
[ "$GO_CONSTANT" = "$GO_DIGEST" ] ||
  fail "$GO_CONSTANT_FILE records $GO_CONSTANT, but the copy hashes to $GO_DIGEST"

[ "$PY_SIZE" = "$EXPECTED_SIZE" ] ||
  fail "$PY_ARTIFACT is $PY_SIZE bytes, expected $EXPECTED_SIZE"

printf '✅ one artifact: %s (%s B) — both copies, both provenance files and both source constants agree\n' \
  "$PY_DIGEST" "$PY_SIZE"