# Project Context

> Single source of truth for project-specific knowledge. All agents load this ONCE.

## Project Overview

- **Name:** rigorix-sdk
- **Version:** 0.1.0
- **Language:** Rust (the verifier crate); `schemas/` is language-neutral
- **Type:** Contract + protocol library (not an application)
- **Repository:** arman-jalili/rigorix-sdk

## What this repo is

The **contract source of truth** for Rigorix, plus a protocol-only Rust verifier:

- `schemas/` — JSON Schemas for the audit envelope, identity claims, policy
  model, and the frozen native API catalog (`schemas/api/catalog.json`,
  ADR-0001). Grounded in rigorix-oss Rust types — **code is truth**; a draft
  that contradicts the code is fixed from the code, never invented.
- `rust/rigorix-verifier` — verifies an envelope's HMAC-SHA256 byte-exact and
  validates it against the schema. **No `rigorix-engine` dependency** (frozen
  struct copies), so any language/runtime can check a trail independently.
- `schemas/fixtures/envelope/` — REAL engine-signed envelopes as the
  conformance corpus (fixed test-only key), exercised by the verifier.
- `docs/` — strategy freezes, contract-sync deltas, ADRs.

There is **no `src/` crate and no application** here; the workspace is
`rust/Cargo.toml` (members: `rigorix-verifier`).

## Core Principles

1. **Code is truth** — schemas mirror rigorix-oss structs (serde field names).
2. **Contract changes are decisions** — a schema edit goes through the drift CI
   story in rigorix-oss and gets a delta note here; never a silent edit.
3. **Additive and serde-defaulted** — new fields are optional; an artifact
   without them stays valid.
4. **Protocol-only** — the verifier never imports the engine; it is the
   independent check.
5. **Governed flows only** — SDK clients expose governed flows; embedded
   execution stays Rust-only via `rigorix-engine`.
6. **Auditable** — every change is diffable and carries a reference.

## Architecture

### Structure

```
rigorix-sdk/
├── schemas/                 # JSON Schemas (contract source of truth)
│   ├── envelope.json        # audit envelope (format v2)
│   ├── claims.json          # identity claims
│   ├── policy.json          # sequence/requirement/approval policy
│   ├── api/catalog.json     # frozen rigorix.* method catalog (ADR-0001)
│   └── fixtures/envelope/   # real engine-signed fixture corpus
├── rust/                    # Cargo workspace (the verifier lives here)
│   └── rigorix-verifier/
├── docs/                    # strategy freezes, contract-sync, ADRs
└── .pi/                     # agent framework
```

### Key Patterns

- **Error handling:** `Result<T, E>` with `thiserror` (`VerifyError`).
- **Schema loading:** `schemas/` resolved via `RIGORIX_SDK_SCHEMAS` or the
  default `../../schemas` relative to the crate.
- **Frozen copies:** the verifier re-declares the envelope structs rather than
  depending on the engine; add a field in the **same struct position** as the
  engine and keep it serde-defaulted.
- **Canonicalization:** HMAC over `serde_json::to_vec` of the envelope with
  `signature = None`; map-typed fields sorted for reproducibility.

## Quality Gates

### Before Commit
```bash
cargo fmt --manifest-path rust/Cargo.toml
```

### Before Push
```bash
cargo test --manifest-path rust/Cargo.toml --workspace
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
```

### Before Merge
```bash
cargo test --manifest-path rust/Cargo.toml --workspace
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo fmt --manifest-path rust/Cargo.toml --check
cargo audit --file rust/Cargo.lock
```

> The Guardian dispatchers under `.pi/scripts/validate-*.sh` detect the Rust
> workspace under `rust/` and `cd` there before running these.

## Scope Classification

| Scope | Files | Lines | Required Validators |
|-------|-------|-------|---------------------|
| Simple | 1 | < 50 | ci-mr (automated) |
| Moderate | 2-5 | 50-200 | architecture-validator |
| Complex | 5-15 | 200-500 | architecture + security |
| Critical | 15+ or core | 500+ | All validators + human |

## Key Files

| File | Purpose |
|------|---------|
| schemas/envelope.json | Audit-envelope contract (format v2) — canonical HMAC shape |
| schemas/policy.json | Sequence / step-requirement / approval policy model |
| schemas/api/catalog.json | Frozen `rigorix.*` native API catalog (ADR-0001) |
| rust/rigorix-verifier/src/lib.rs | Protocol-only HMAC + schema verifier |
| schemas/fixtures/envelope/ | Real engine-signed conformance corpus |
| docs/adr/ADR-0001-native-api-catalog.md | The frozen native API catalog decision |

## Commands

| Command | Purpose |
|---------|---------|
| `cargo build --manifest-path rust/Cargo.toml` | Build the workspace |
| `cargo test --manifest-path rust/Cargo.toml --workspace` | Run tests |
| `cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings` | Lint |
| `cargo audit --file rust/Cargo.lock` | Security audit |
