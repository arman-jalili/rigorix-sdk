## Summary

Keeps the shared `rigorix.*` namespace honest. The enterprise Execution API
(`rigorix-enterprise` #206 / PR #208) registers **`rigorix.auth.verify`**, but it
was absent from the frozen catalog — drift in a namespace that ADR-0001 D3
declares **closed**. This PR declares the method (contract-first), documents the
closed-namespace rule, and adds a verifier guard so any future server-side
method must be declared to pass CI.

Closes #15.

## Decision: declare (not fold)

`rigorix.auth.verify` is an org-side **JWKS verification** of an OSS-attested
claim returning the verified `IdentityClaim` — distinct from
`rigorix.auth.status` (reports the local session status). The enterprise
genuinely needs the call, so the SDK owns it:

- `rigorix-enterprise core/src/execution_api/application/catalog.rs:74,182` —
  `MethodSpec` (query / session / no MCP tool) → `claim.verify(scope, p)`
- result `{ "claim": <IdentityClaim> }` (`.../domain/identity.rs`)

## Changes

**`schemas/api/catalog.json`**
- New top-level `description` documenting that `rigorix.*` is a **CLOSED**
  namespace: a server implements a subset, never an extension.
- Declares `rigorix.auth.verify` (query / `session` / `mcpTool: null`, additive
  within `apiVersion` 1.x) with `$defs.authVerifyParams`
  (`{ attestation: string }`) and `$defs.authVerifyResult`
  (`{ claim: identityClaim }`), plus an `$defs.identityClaim` mirroring
  `../claims.json#/$defs/identityClaim`.

**`schemas/api/catalog.schema.json`** — allows the top-level `description`.

**`rust/rigorix-verifier`**
- `verify_catalog_subset(candidate)`: reads the frozen method set and fails on
  any undeclared `rigorix.*` name (`VerifyError::UndeclaredMethod`).
- `catalog_integrity` now asserts `rigorix.auth.verify`'s shape (query/session/
  no-MCP-tool, resolvable params/result refs) and that the catalog documents the
  closed namespace.
- New test: the enterprise subset passes; `rigorix.auth.bogus` is rejected.

**Docs** — `schemas/api/README.md` rule 6 (closed namespace),
`schemas/api/method-catalog.md` (lists the method, points at `catalog.json` as
authoritative), contract-sync delta note.

## Verification

```
cd rust
cargo build
cargo test --workspace        # 23 passed, 1 ignored (fixture generator)
cargo clippy --all-targets -- -D warnings
cargo fmt --check
cargo audit                   # 0 advisories
```

`catalog_integrity` validates `catalog.json` against `catalog.schema.json` and
resolves every method's params/result refs. The subset guard proves AC2.

## Cross-repo follow-up (not this PR)

`rigorix-oss/server/tests/catalog_parity.rs` currently asserts the OSS in-code
catalog **equals** the SDK catalog. With the closed/subset model it should switch
to `verify_catalog_subset` — the OSS server is a subset of the shared namespace,
not the whole of it. Flagged in the contract-sync delta note.

## Out of scope

- The enterprise implementation (rigorix-enterprise #206 / PR #208).
- Typed clients (SDK-C4 / #11) and the SSE spec (SDK-C1 / #10 — already merged).
