#!/usr/bin/env bash
# SDK-CRATES-0.4.0 — prove the distribution carries the release payload, with
# RIGORIX_SDK_SCHEMAS unset:
#   * ADR-016 Phase C `anchor_head` (0.2.0), and
#   * the structured attribution reason on precondition findings (0.4.0).
#
# Two gates:
#   1. `cargo package -p rigorix-schemas` (verified build) → the produced
#      `.crate` must contain `schemas/envelope.json` WITH `anchor_head` and the
#      anchored fixture. This is the self-contained corpus a crates.io consumer
#      gets.
#   2. A CLEAN scratch consumer (outside the workspace) that depends on
#      `rigorix-verifier` verifies the anchored fixture byte-exact via the
#      embedded corpus (no env override).
#
# `cargo package -p rigorix-verifier` / `cargo publish --dry-run` cannot run
# until `rigorix-schemas` 0.2.0 is on crates.io (its exact-version dep is not
# resolvable — cargo needs the registry even with `--no-verify`). The workspace
# build used here is the same source the `.crate` will contain; run the package
# gate for the verifier immediately after publishing `rigorix-schemas` 0.2.0.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rust_dir="$(cd "$here/.." && pwd)"
version="$(sed -nE 's/^version = "([^"]+)"/\1/p' "$rust_dir/Cargo.toml" | head -1)"
echo "packaged-crate smoke: version=$version"

work="$(mktemp -d)"
cleanup() { find "$work" -mindepth 1 -delete 2>/dev/null || true; rmdir "$work" 2>/dev/null || true; }
trap cleanup EXIT

cd "$rust_dir"

# ── Gate 1: the packaged schemas crate carries the Phase C contract ──────────
cargo package -p rigorix-schemas --allow-dirty >/dev/null
mkdir -p "$work/pkg"
tar -xzf "$rust_dir/target/package/rigorix-schemas-$version.crate" -C "$work/pkg"
schemas_pkg="$work/pkg/rigorix-schemas-$version"
grep -q '"anchor_head"' "$schemas_pkg/schemas/envelope.json" \
  || { echo "FAIL: packaged rigorix-schemas $version envelope.json lacks anchor_head"; exit 1; }
[[ -f "$schemas_pkg/schemas/fixtures/envelope/envelope-anchored-signed.json" ]] \
  || { echo "FAIL: packaged rigorix-schemas lacks the anchored fixture"; exit 1; }
# 0.4.0 payload: the structured attribution reason + its re-signed fixture. This
# release's entire contract change, so assert it is actually in the .crate.
grep -q '"attribution"' "$schemas_pkg/schemas/envelope.json" \
  || { echo "FAIL: packaged rigorix-schemas $version envelope.json lacks the 0.4.0 attribution reason"; exit 1; }
[[ -f "$schemas_pkg/schemas/fixtures/envelope/envelope-precondition-signed.json" ]] \
  || { echo "FAIL: packaged rigorix-schemas lacks the precondition fixture"; exit 1; }
echo "gate 1: packaged rigorix-schemas-$version carries anchor_head + attribution + fixtures OK"

# ── Gate 2: clean scratch consumer verifies the anchored fixture (no env) ────
proj="$work/consumer"
mkdir -p "$proj/src"
cat > "$proj/Cargo.toml" <<TOML
[package]
name = "packaged-smoke"
version = "0.0.0"
edition = "2021"

[dependencies]
serde_json = "1"
rigorix-schemas = { path = "$rust_dir/rigorix-schemas" }
rigorix-verifier = { path = "$rust_dir/rigorix-verifier" }
TOML

cat > "$proj/src/main.rs" <<'RS'
fn main() {
    // Embedded corpus only — RIGORIX_SDK_SCHEMAS must be unset.
    let anchored = rigorix_schemas::fixture("envelope/envelope-anchored-signed.json")
        .expect("corpus must embed the anchored fixture");
    rigorix_verifier::verify_signature(anchored, "fixture-hmac-key-2026")
        .expect("verifier must verify the anchored fixture byte-exact");
    rigorix_verifier::validate_schema(anchored).expect("anchored fixture validates");
    assert!(
        rigorix_schemas::schema("envelope.json").is_some_and(|s| s.contains("\"anchor_head\"")),
        "schemas must declare anchor_head"
    );
    // Phase A regression guard: a local chain fixture (no anchor_head) still verifies.
    let chain = rigorix_schemas::fixture("integrity/chain.json").expect("chain fixture");
    let envelopes: Vec<rigorix_verifier::AuditEnvelope> =
        serde_json::from_str(chain).expect("chain parses");
    rigorix_verifier::verify_chain(&envelopes).expect("verifier verifies the chain");

    // 0.4.0 payload: the precondition fixture carries the structured attribution
    // reason and must verify byte-exact from the embedded corpus. This is the
    // whole contract change of the release, so prove it end to end rather than
    // trusting the version bump.
    let pre = rigorix_schemas::fixture("envelope/envelope-precondition-signed.json")
        .expect("corpus must embed the precondition fixture");
    assert!(
        pre.contains("\"attribution\""),
        "precondition fixture must carry the 0.4.0 attribution reason"
    );
    rigorix_verifier::verify_signature(pre, "fixture-hmac-key-2026")
        .expect("verifier must verify the precondition fixture byte-exact");
    println!("gate 2: clean consumer verifies anchored + precondition fixtures + chain OK");
}
RS

unset RIGORIX_SDK_SCHEMAS
(cd "$proj" && CARGO_TARGET_DIR="$rust_dir/target" cargo run --quiet)
echo "packaged-crate smoke: PASS"
