# Implementation Plan: issue/15

**Branch:** `issue/15`
**Base:** `main` (`16a41a1`, includes #10 + #12)
**Issue:** #15 — SDK-C5: Catalog parity — declare `rigorix.auth.verify` (or fold
it) + a catalog-subset conformance guard

## Classification

Contract slice. Scope: **Complex** (catalog contract change + new verifier guard).

## Decision: declare (option a)

`rigorix-enterprise` #206 / PR #208 registers `rigorix.auth.verify`
(`core/src/execution_api/application/catalog.rs:74` `MethodSpec`; dispatch at
`:182` → `claim.verify(scope, p)`). It is a JWKS verification request returning
the verified claim — distinct from `rigorix.auth.status` (reports the local
session). The namespace is closed (ADR-0001 D3), so the SDK declares the method
rather than letting a server extend `rigorix.*`.

## Code truth (grounded)

| Source | What |
|---|---|
| `rigorix-enterprise/core/src/execution_api/application/catalog.rs` | `MethodSpec { name, kind: Query, auth: Session, mcp_tool: None }` |
| `.../application/dto.rs` | `AttestationParams { attestation: String }` |
| `.../application/services.rs` | result `{ "claim": claim.identity_claim() }` → full `IdentityClaim` |
| `rigorix-enterprise/core/src/auth_authorization/domain/identity.rs` | `IdentityClaim` field order — matches `schemas/claims.json` `$defs.identityClaim` |
| `schemas/api/catalog.json` | the frozen catalog (closed namespace) |

## Deliverables

1. `schemas/api/catalog.json`:
   - top-level `description` documenting the **closed namespace**;
   - method `rigorix.auth.verify` (query / `session` / `mcpTool: null`);
   - `$defs.authVerifyParams`, `$defs.authVerifyResult`, `$defs.identityClaim`.
2. `schemas/api/catalog.schema.json` — allow the top-level `description`.
3. `rust/rigorix-verifier`: `verify_catalog_subset(candidate)` +
   `VerifyError::UndeclaredMethod`; `catalog_integrity` asserts the new method's
   shape and the closed-namespace description; a test rejects an undeclared name.
4. `schemas/api/README.md` rule 6 (closed namespace) + `method-catalog.md`.
5. Contract-sync delta note.

## Validation

- [x] `cargo build`
- [x] `cargo test --workspace` — 23 passed, 1 ignored
- [x] `cargo clippy --all-targets -- -D warnings`
- [x] `cargo fmt --check`
- [x] `cargo audit`
- [x] catalog.json validates against catalog.schema.json

## Cross-repo follow-up

`rigorix-oss/server/tests/catalog_parity.rs` asserts the OSS in-code catalog
**equals** the SDK catalog. Under the closed/subset model it should use
`verify_catalog_subset` (the OSS server is a subset, not the whole namespace).

## Status

- [x] Implemented
- [x] Local deterministic checks green
- [ ] MR pushed
- [ ] Merged
