# Contract Sync — Delta (2026-10-13)

**Status:** Applied contract delta (SDK issue #44, `ISSUE-SDK-CATALOG-PROJECTION-METHOD`).
**Scope:** `schemas/api/catalog.json` + new `schemas/api/authority-fact-bundle.json`.
**Base:** the 2026-09-06 contract-sync design (`docs/contract-sync-2026-09-06.md`).

## What changed

| Artifact | Change |
|---|---|
| `schemas/api/catalog.json` | Additive method `rigorix.audit.authorityFacts` (query, auth `session`, `mcpTool` `rigorix_audit_authority_facts`), params `#/$defs/authorityFactsParams`, result `#/$defs/authorityFactsResult`. Method count 23 → 24. |
| `schemas/api/authority-fact-bundle.json` | **New** frozen schema, `$id` `https://rigorix.dev/schemas/api/authority-fact-bundle-v1.json`. |
| `apiVersion` | Unchanged (`1.0.0`). Additive within the major (ADR-0001 D3). |

No existing method, field, type, or requirement changed. No envelope canonical-form
change: old verifiers still verify envelopes (acceptance criterion 6).

## Why (code is truth)

The projection already exists in `rigorix-oss` — `engine/src/audit/domain/authority_fact.rs`
(`AuthorityFactBundle`, `AuthorityFactProjection`, `AuthorityFact`, `ClaimCeiling`,
`AnchorRef`, `EvidenceRef`) and `engine/src/audit/application/projection.rs`
(`ProjectAuthorityFacts`), per the normative spec
`rigorix-oss/docs/spec/consequence-gating-v1.md` §4.3. This delta mirrors those
structs field-for-field; it does not design a new artifact.

The SDK catalog is the **first** of the three-repo change (spec
`ISSUE-PROJECTION-SURFACES`): the closed `rigorix.*` namespace means a client or
verifier built against the old catalog will not accept the new method, so OSS
cannot ship its MCP tool ahead of this. Sequencing is the point, exactly as the
0.3.0 → 0.4.0 attribution train established.

## Shape decision (recorded)

- **Standalone file, not inline `$defs`.** The bundle is a multi-part, re-derivable
  artifact like `api/history-slice.json`; `$defs` holds only method-local shapes
  (`auditHistoryResult` `$ref`s `history-slice-v1.json` the same way). `api/catalog.json`
  has no second artifact dialect.
- **`envelopes[]` `$ref`s `envelope-v2.json` by `$id`.** The bundle never
  re-declares envelope fields — that would be the very "second dialect" the
  standalone file exists to avoid.
- **Auth `session`, not `admin`.** `admin` means "requires an enterprise scope"
  (the catalog's own `authLevels`), but the projection is an OSS capability
  (spec + engine landed in rigorix-oss). Gating it behind an enterprise scope
  would make a plain OSS deployment unable to expose it. `session` matches the
  `rigorix.audit.read/list/summary` family.
- **Inline `envelopes[]`, with declared disclosure.** Spec §4.3 and the
  `AuthorityFactBundle` struct normatively define the bundle as *the projection +
  the history it was derived from*; a URI list would be a different artifact.
  The method description states that the caller receives the signed envelopes,
  not a summary (re-derivation requires them).

## Verification

- `rust/rigorix-verifier`:
  - `catalog_integrity` (existing) — method `$ref`s resolve in `$defs`.
  - `all_schemas_compile` — the new bundle schema compiles with `envelope.json`
    registered as the cross-file resource.
  - `catalog_declares_authority_fact_projection_additively` (new) — freezes the
    method shape, the standalone `$id` result, and the envelope `$ref`.
- `rust/rigorix-client`, `typescript-client`, `go/client` — catalog-drift tests
  require every frozen method to have an explicit binding; the new entry is
  `server_only` / `ServerOnly` (no typed wrapper yet).
- Python/TypeScript `_schemas` copies and the Go corpus are **generated** from
  `schemas/`; their sync tests re-derive and compare byte-for-byte.

## Release sequencing (acceptance criterion 5) — SHIPPED

`0.5.0` is published on every channel — crates.io (`rigorix-schemas`,
`rigorix-verifier`), PyPI (`rigorix-verifier`), npm (`rigorix-verifier`,
`rigorix-client`) — under tags `rust-v0.5.0` and `v0.5.0`, and the registry
install smoke job is green. `rust/RELEASING.md` carries the requirement in its
0.5.0 release notes.

`rigorix-oss` `ISSUE-PROJECTION-SURFACES` may now ship its MCP tool — but only
after the consumers move, because 0.x semver means `^0.4` does **not** resolve
`0.5.0`. `rigorix-oss/server` and `rigorix-enterprise/core` pin
`rigorix-verifier = "0.5"`.
