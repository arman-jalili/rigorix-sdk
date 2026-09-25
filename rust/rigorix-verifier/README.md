# rigorix-verifier

Protocol-only verification of Rigorix audit envelopes and the frozen contract
surface. Independent, self-contained, and **engine-free** (strategy freeze D-1):
it depends on `rigorix-schemas` for the contracts, never on `rigorix-engine`.

- **HMAC-SHA256** integrity over the documented canonical form
  (`signature` nulled) — byte-exact with the engine's `compute_signature`.
- **JSON Schema** conformance (draft 2020-12) for envelope / claims / policy /
  catalog / errors / events / ADR-016 anchor artifacts.
- **ADR-016 chains**: per-producer sequence + `prev_hash` continuity, with gaps
  accepted **iff** covered by a valid Ed25519-signed compaction checkpoint.
- **Native-API catalog** integrity + the closed-namespace
  `verify_catalog_subset` guard (ADR-0001 D3).
- **Engine-signed fixture** verification, byte-exact, from any language.

## Resolution (self-contained)

The verifier reads contracts from, in order:

1. `RIGORIX_SDK_SCHEMAS` — an explicit external corpus (CI/local override).
2. The **embedded `rigorix-schemas`** corpus — the published path.

There is no repo-relative fallback, so a published/`cargo package`d verifier is
self-contained: `cargo test` passes with `RIGORIX_SDK_SCHEMAS` unset.

## Usage

```rust
use rigorix_verifier::{validate_schema, verify_catalog_subset, verify_chain, verify_signature};

// Byte-exact HMAC check of an engine-signed envelope.
verify_signature(&envelope_json, "fixture-hmac-key-2026")?;

// Schema conformance.
validate_schema(&envelope_json)?;

// Closed `rigorix.*` namespace: a server may only serve declared methods.
verify_catalog_subset(&["rigorix.plan", "rigorix.auth.verify"])?;

// ADR-016 local chain (sequence monotonic + prev_hash continuity).
verify_chain(&envelopes)?;
# Ok::<(), rigorix_verifier::VerifyError>(())
```

## Packaging

```bash
cd rust
cargo package -p rigorix-verifier      # ships no schemas of its own
cargo publish -p rigorix-verifier --dry-run
```

A published verifier carries no schema files: it embeds them through
`rigorix-schemas` (publish that crate first).

## License

Apache-2.0 (repo-wide, matching the workspace).
