#!/usr/bin/env bash
# ============================================================================
# validate-runtime-wiring.sh — ADR-009 production-reachability dispatcher
#
# Deterministic check: every application-layer service must be referenced from
# production code OUTSIDE its own module and OUTSIDE tests. A service whose
# only callers are its own tests is implemented-but-unwired (dead code with a
# test suite) — the recurring rigorix pattern ADR-009 fixes.
#
# Delegates to languages/<lang>/check_runtime_reachability.sh.
# Usage: bash .pi/scripts/validate-runtime-wiring.sh [--root <dir>]
# Exit:  0 all services reachable (or language not yet covered)
#        1 unreachable service(s) — one 'file: [runtime-reachability] ...' line each
# ============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(pwd)"
if [ "${1:-}" = "--root" ] && [ -n "${2:-}" ]; then ROOT="$2"; fi
cd "$ROOT" || exit 1

# ── language detection (repo root OR a workspace subdirectory) ───────────────
# Unlike a single-language project, this repo keeps the Rust workspace under
# rust/ (schemas/ and future /python, /typescript live beside it). Detect the
# language at the root first, then one level down, and run the language
# validator from the directory that owns the manifest.
detect_language() {
    for dir in "." "rust"; do
        if [ -f "$dir/poetry.lock" ] || [ -f "$dir/pyproject.toml" ]; then echo "${dir}|python"; return; fi
    done
    for dir in "." "rust" "go" "java" "typescript"; do
        if [ -f "$dir/Cargo.lock" ] || [ -f "$dir/Cargo.toml" ]; then echo "${dir}|rust"; return; fi
        if [ -f "$dir/go.mod" ]; then echo "${dir}|go"; return; fi
        if [ -f "$dir/pom.xml" ] || [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ]; then echo "${dir}|java"; return; fi
        if [ -f "$dir/package.json" ]; then echo "${dir}|typescript"; return; fi
    done
    echo ".|unknown"
}

DETECTED="$(detect_language)"
PROJECT_DIR="${DETECTED%%|*}"
LANG="${DETECTED##*|}"
SELF="$(basename "$0")"

# Language scripts live under the framework's own .pi/scripts/languages/ —
# not next to a .agents/ copy of this dispatcher.
ROOT="${SCRIPT_DIR}"
[ -d "${ROOT}/languages" ] || ROOT="$(cd "${SCRIPT_DIR}/../.." 2>/dev/null && pwd)/.pi/scripts"
LANG_SCRIPT="${ROOT}/languages/${LANG}/${SELF}"

if [ -f "$LANG_SCRIPT" ]; then
    if [ "$PROJECT_DIR" != "." ]; then cd "$PROJECT_DIR"; fi
    exec bash "$LANG_SCRIPT" "$@"
else
    echo "No validator for language: ${LANG} (looked for ${LANG_SCRIPT})"
    exit 0
fi
