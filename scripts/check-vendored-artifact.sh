#!/usr/bin/env bash
# check-vendored-artifact.sh — the two vendored copies are one fact, and that fact
# is the published asset.
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
# What those four checks cannot see (SDL, #104): every one of them is an internal
# comparison, so all five recordings can move together to a value no download
# reproduces — which is exactly the state #78 found. Hence:
#   --verify-upstream  compare the vendored bytes to the release asset the
#                      PROVENANCE files name, through the release API. Network and
#                      `gh` are required, so it runs on a schedule (audit.yml) and
#                      on request, never in a pull request.
#   --self-test        show that each check above can fail: four planted drifts,
#                      each of which must be rejected naming the file it changed.
#
# Usage:
#   bash scripts/check-vendored-artifact.sh [--self-test] [--verify-upstream]
#                                           [--root DIR]
# Exit: 0 = one fact; 1 = drift (message names the file); 2 = not verified
#       (no `gh`, no network, or a release that records no digest) — never 0.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TREE="$ROOT"
SELF_TEST=0
VERIFY_UPSTREAM=0

while [ $# -gt 0 ]; do
  case "$1" in
    --self-test) SELF_TEST=1 ;;
    --verify-upstream) VERIFY_UPSTREAM=1 ;;
    --root) TREE="$2"; shift ;;
    *) echo "check-vendored-artifact: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

PY_ARTIFACT="python/rigorix_verifier/_wasm/rigorix_gate_wasi.wasm"
GO_ARTIFACT="go/gate/testdata/rigorix_gate_wasi.wasm"
PY_PROVENANCE="python/rigorix_verifier/_wasm/PROVENANCE.md"
GO_PROVENANCE="go/gate/testdata/PROVENANCE.md"
PY_CONSTANT_FILE="python/rigorix_verifier/binding/loader.py"
GO_CONSTANT_FILE="go/gate/artifact.go"
EXPECTED_SIZE=1899431

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

check() {
  local py_digest go_digest py_size go_size
  # 1. both copies exist.
  for copy in "$PY_ARTIFACT" "$GO_ARTIFACT"; do
    [ -f "$TREE/$copy" ] || fail "missing vendored copy $copy"
  done

  py_digest="$(digest_of "$TREE/$PY_ARTIFACT")"
  go_digest="$(digest_of "$TREE/$GO_ARTIFACT")"
  py_size="$(size_of "$TREE/$PY_ARTIFACT")"
  go_size="$(size_of "$TREE/$GO_ARTIFACT")"

  # 2. the copies are byte-identical. Name the file that has to change.
  if [ "$py_digest" != "$go_digest" ]; then
    fail "the two vendored copies differ: $GO_ARTIFACT is $go_digest ($go_size B), but $PY_ARTIFACT is $py_digest ($py_size B) — update both from the same build"
  fi

  # 3. each PROVENANCE.md records its own copy.
  local pair provenance rest digest size recorded_digest_value recorded_size_value
  for pair in "$PY_PROVENANCE:$py_digest:$py_size" "$GO_PROVENANCE:$go_digest:$go_size"; do
    provenance="${pair%%:*}"
    rest="${pair#*:}"
    digest="${rest%%:*}"
    size="${rest##*:}"
    recorded_digest_value="$(recorded_digest "$TREE/$provenance")"
    [ "$recorded_digest_value" = "$digest" ] ||
      fail "$provenance records sha256 $recorded_digest_value, but the copy hashes to $digest — the provenance must change with the artifact"
    recorded_size_value="$(recorded_size "$TREE/$provenance")"
    [ "$recorded_size_value" = "$size" ] ||
      fail "$provenance records size $recorded_size_value, but the copy is $size bytes"
  done

  # 4. both source constants agree with the bytes. The loader that refuses a
  #    mismatch must refuse over the same digest the other language trusts.
  local py_constant go_constant
  py_constant="$(recorded_constant "$TREE/$PY_CONSTANT_FILE" ARTIFACT_SHA256)"
  go_constant="$(recorded_constant "$TREE/$GO_CONSTANT_FILE" artifactSHA256)"
  [ "$py_constant" = "$py_digest" ] ||
    fail "$PY_CONSTANT_FILE records $py_constant, but the copy hashes to $py_digest"
  [ "$go_constant" = "$go_digest" ] ||
    fail "$GO_CONSTANT_FILE records $go_constant, but the copy hashes to $go_digest"

  [ "$py_size" = "$EXPECTED_SIZE" ] ||
    fail "$PY_ARTIFACT is $py_size bytes, expected $EXPECTED_SIZE"

  printf '✅ one artifact: %s (%s B) — both copies, both provenance files and both source constants agree\n' \
    "$py_digest" "$py_size"
}

# The release the PROVENANCE files name: `**source:** \`owner/repo\`, tag \`vX\``.
upstream_coordinate() {
  local file="$1" line
  line="$(grep -n -E '\*\*source:\*\* `[^`]+/[^`]+`, tag `[^`]+`' "$file" | head -1)"
  [ -n "$line" ] || return 1
  printf '%s\n' "$(printf '%s' "${line#*:}" | grep -Eo '`[^`]+/[^`]+`' | head -1 | tr -d '`') $(printf '%s' "${line#*:}" | grep -Eo 'tag `[^`]+`' | head -1 | tr -d '`' | sed 's/^tag //')"
}

verify_upstream() {
  local repo tag asset published published_size vendored vendored_size provenance
  provenance="$1"
  command -v gh >/dev/null 2>&1 ||
    { printf '⚠ not verified: gh is not installed, so the release asset was not compared\n' >&2; return 2; }

  read -r repo tag <<<"$(upstream_coordinate "$TREE/$provenance")"
  if [ -z "${repo:-}" ] || [ -z "${tag:-}" ]; then
    printf '⚠ not verified: %s names no `**source:** \\`owner/repo\\`, tag \\`vX\\`` line\n' "$provenance" >&2
    return 2
  fi

  asset="$(basename "$PY_ARTIFACT")"
  if ! json="$(gh release view "$tag" --repo "$repo" --json assets 2>/dev/null)"; then
    printf '⚠ not verified: the release API could not be read for %s %s (network or auth)\n' "$repo" "$tag" >&2
    return 2
  fi
  published="$(printf '%s' "$json" | python3 -c '
import json, sys
asset = sys.argv[1]
for entry in json.load(sys.stdin).get("assets", []):
    if entry.get("name") == asset:
        print(entry.get("size", ""), entry.get("digest") or "")
        break
' "$asset")"
  if [ -z "$published" ]; then
    printf '⚠ not verified: %s %s publishes no asset named %s\n' "$repo" "$tag" "$asset" >&2
    return 2
  fi
  published_size="${published%% *}"
  published="${published#* }"
  if [ -z "$published" ]; then
    printf '⚠ not verified: %s %s records no digest for %s\n' "$repo" "$tag" "$asset" >&2
    return 2
  fi
  published="${published#sha256:}"

  vendored="$(digest_of "$TREE/$PY_ARTIFACT")"
  vendored_size="$(size_of "$TREE/$PY_ARTIFACT")"
  if [ "$published" != "$vendored" ]; then
    fail "the vendored copy is not the published asset: $repo $tag publishes $published ($published_size B), the copy hashes to $vendored ($vendored_size B)"
  fi
  [ "$published_size" = "$vendored_size" ] ||
    fail "the vendored copy and the published asset disagree on size: published $published_size B, copy $vendored_size B"
  printf '✅ published asset: %s %s — %s (%s B) equals the vendored copy (%s)\n' \
    "$repo" "$tag" "$published" "$published_size" "$asset"
}

fixture() {
  # Six recording files, copied from the real tree; a plant never touches it.
  local tmp="$1" path
  for path in "$PY_ARTIFACT" "$GO_ARTIFACT" "$PY_PROVENANCE" "$GO_PROVENANCE" \
              "$PY_CONSTANT_FILE" "$GO_CONSTANT_FILE"; do
    mkdir -p "$tmp/$(dirname "$path")"
    cp "$ROOT/$path" "$tmp/$path"
  done
}

plant_byte() {
  python3 - "$1" <<'PY'
import sys
path = sys.argv[1]
data = bytearray(open(path, "rb").read())
data[1024] ^= 0xFF
open(path, "wb").write(data)
PY
}

plant_digest() {
  python3 - "$1" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
open(path, "w", encoding="utf-8").write(
    re.sub(r"[0-9a-f]{64}", "0" * 64, text, count=1)
)
PY
}

plant_size() {
  python3 - "$1" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
open(path, "w", encoding="utf-8").write(
    re.sub(r"\b1,899,431\b", "1,899,432", text, count=1)
)
PY
}

plant_constant() {
  python3 - "$1" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
open(path, "w", encoding="utf-8").write(
    re.sub(r"([0-9a-f]{64})", lambda m: "f" * 64, text, count=1)
)
PY
}

self_test() {
  local tmp failures=0 case_name out expect
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp' >/dev/null 2>&1 || true" EXIT

  expect_clean() {
    local dir="$1"
    if out="$(TREE="$dir" check 2>&1)"; then
      case "$out" in *"✅ one artifact:"*) : ;;
        *) echo "❌ self-test: the clean fixture passed without a verdict"; failures=$((failures + 1)) ;; esac
    else
      echo "❌ self-test: the clean fixture failed — the guard rejects the real tree"
      printf '%s\n' "$out" | tail -2
      failures=$((failures + 1))
    fi
  }

  expect_planted() {
    local dir="$1" wanted="$2" label="$3"
    if out="$(TREE="$dir" check 2>&1)"; then
      echo "❌ self-test: planted drift ($label) was accepted"
      failures=$((failures + 1))
      return
    fi
    case "$out" in
      *"$wanted"*) ;;
      *) echo "❌ self-test: planted drift ($label) was not named ($wanted)"; failures=$((failures + 1)) ;;
    esac
  }

  fixture "$tmp/clean";       expect_clean "$tmp/clean"
  fixture "$tmp/copy";        plant_byte     "$tmp/copy/$GO_ARTIFACT"
  expect_planted "$tmp/copy" "$GO_ARTIFACT" "a byte in one copy"
  fixture "$tmp/digest";      plant_digest   "$tmp/digest/$PY_PROVENANCE"
  expect_planted "$tmp/digest" "$PY_PROVENANCE" "a digest in one provenance"
  fixture "$tmp/size";        plant_size     "$tmp/size/$GO_PROVENANCE"
  expect_planted "$tmp/size" "$GO_PROVENANCE" "a size in one provenance"
  fixture "$tmp/constant";    plant_constant "$tmp/constant/$GO_CONSTANT_FILE"
  expect_planted "$tmp/constant" "$GO_CONSTANT_FILE" "a source constant"

  if [ "$failures" -gt 0 ]; then
    echo "❌ check-vendored-artifact self-test: $failures case(s) wrong"
    return 1
  fi
  echo "✅ 4 planted drift(s) rejected, 1 clean fixture accepted — each rejection names the file that changed"
  return 0
}

if [ "$SELF_TEST" -eq 1 ]; then
  self_test
  exit $?
fi

if [ "$VERIFY_UPSTREAM" -eq 1 ]; then
  # First the internal fact, then the external one: a drift between the copies is
  # cheaper to diagnose than a drift from the page.
  check
  verify_upstream "$PY_PROVENANCE"
  exit $?
fi

check