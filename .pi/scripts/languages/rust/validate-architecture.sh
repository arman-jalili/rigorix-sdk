#!/usr/bin/env bash
# ============================================================================
# validate-architecture.sh — Rust (rigorix-sdk contract-repo profile)
#
# rigorix-sdk is a CONTRACT library, not a DDD application: `schemas/` is the
# source of truth and `rust/rigorix-verifier` is a protocol-only crate. The
# generic clean-architecture layer check (`src/domain|application|infrastructure`)
# does not apply. This validator enforces the invariants that actually matter
# here. The dispatcher cd's into the Rust workspace (rust/) before running.
# ============================================================================
set -euo pipefail

PASS_COUNT=0
ERRORS=()
WARNINGS=()

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}✅ PASS${NC} $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}❌ FAIL${NC} $1"; ERRORS+=("$1"); }
warn() { echo -e "${YELLOW}⚠️  WARN${NC} $1"; WARNINGS+=("$1"); }

echo "============================================"
echo "  Architecture Validation (Rust — rigorix-sdk)"
echo "============================================"
echo ""

# Resolve layout. The dispatcher may run us from the workspace root (rust/)
# or, for this single-crate workspace, from the crate dir (rigorix-verifier/).
WS="$(pwd)"
if [ -d "$WS/rigorix-verifier" ]; then
    CRATE="$WS/rigorix-verifier"
    REPO_ROOT="$(cd "$WS/.." && pwd)"
elif [ -f "$WS/Cargo.toml" ] && [ -d "$WS/src" ]; then
    CRATE="$WS"
    REPO_ROOT="$(cd "$WS/../.." && pwd)"
else
    CRATE="$WS/rust/rigorix-verifier"
    REPO_ROOT="$WS"
fi

# ---------------------------------------------------------------------------
# 1. Contract source of truth
# ---------------------------------------------------------------------------
echo "--- Contract schemas (source of truth) ---"
SCHEMAS="$REPO_ROOT/schemas"
MISSING=""
for s in envelope.json claims.json policy.json; do
    [ -f "$SCHEMAS/$s" ] || MISSING="$MISSING $s"
done
if [ -z "$MISSING" ]; then
    pass "Contract schemas present (envelope/claims/policy)"
else
    fail "Missing contract schema(s):$MISSING"
fi
if [ -f "$SCHEMAS/api/catalog.json" ]; then
    pass "Frozen native API catalog present (schemas/api/catalog.json)"
else
    warn "No schemas/api/catalog.json (native API catalog)"
fi

# ---------------------------------------------------------------------------
# 2. Protocol-only verifier (the core architectural invariant)
# ---------------------------------------------------------------------------
echo ""
echo "--- Verifier is protocol-only (no rigorix-engine dependency) ---"
ENGINE_DEPS=$(grep -rEl '^\s*rigorix-engine\s*=' "$REPO_ROOT/rust" --include=Cargo.toml 2>/dev/null | wc -l | tr -d ' ') || true
if [ "$ENGINE_DEPS" -eq 0 ]; then
    pass "No rigorix-engine dependency in the workspace (independent verifier)"
else
    fail "rigorix-engine dependency found in $ENGINE_DEPS Cargo.toml file(s) — the verifier must stay protocol-only"
fi

# ---------------------------------------------------------------------------
# 3. Library crate shape
# ---------------------------------------------------------------------------
echo ""
echo "--- Crate shape ---"
if [ -f "$CRATE/src/lib.rs" ]; then
    pass "rigorix-verifier is a library crate (src/lib.rs)"
else
    fail "rigorix-verifier/src/lib.rs missing"
fi

# ---------------------------------------------------------------------------
# 4. Canonical references
# ---------------------------------------------------------------------------
echo ""
echo "--- Canonical references ---"
[ -d "$REPO_ROOT/.pi/architecture" ] && pass "Architecture workspace present (.pi/architecture)" \
    || warn "No .pi/architecture/ directory"
ADR_COUNT=$(find "$REPO_ROOT/docs/adr" -name 'ADR-*.md' 2>/dev/null | wc -l | tr -d ' ') || true
if [ "$ADR_COUNT" -gt 0 ]; then
    pass "ADRs present ($ADR_COUNT in docs/adr/)"
else
    warn "No ADRs found in docs/adr/"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo "  Summary"
echo "============================================"
echo -e "  Passed:   ${GREEN}${PASS_COUNT}${NC}"
echo -e "  Failed:   ${RED}${#ERRORS[@]}${NC}"
echo ""
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "FAILURES:"
    for err in "${ERRORS[@]}"; do echo "  - $err"; done
    exit 1
fi
echo -e "${GREEN}Architecture validation completed.${NC}"
exit 0
