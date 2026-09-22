#!/usr/bin/env bash
# ============================================================================
# validate-ci.sh — Dispatcher
#
# Detects the project language and delegates to the language-specific script.
# Language-specific scripts live in: .pi/scripts/languages/<lang>/validate-ci.sh
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
