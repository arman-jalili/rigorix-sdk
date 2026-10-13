## Summary

Closes #44. Adds the authority-fact projection to the frozen `rigorix.*` catalog so
`rigorix-oss` can expose it over the governed MCP/HTTP surface. The **SDK contract
lands first** — a verifier or client built against the old catalog will not accept
an unknown method, so OSS cannot ship its tool ahead of this without breaking parity
(same 0.3.0 → 0.4.0 attribution sequencing).

The artifact is the `AuthorityFactBundle` from the consequence-gating spec §4.3,
mirrored field-for-field from `rigorix-oss`
`engine/src/audit/domain/authority_fact.rs` (code is truth) — this PR does not
design a new artifact.

## The frozen contract (decisions recorded in `docs/contract-sync-2026-10-13.md`)

| Field | Value |
|---|---|
| method | `rigorix.audit.authorityFacts` |
| kind / auth | `query` / `session` |
| mcpTool | `rigorix_audit_authority_facts` |
| params | `{ subjects: string[] (required), producer_id?: string }` |
| result | `$ref` → `https://rigorix.dev/schemas/api/authority-fact-bundle-v1.json` |

Rationale for the shape:

- **Standalone file, not inline `$defs`.** The bundle is a multi-part, re-derivable
  artifact like `api/history-slice.json`; `auditHistoryResult` addresses it the same
  way. `catalog.json` `$defs` stay method-local.
- **`envelopes[]` `$ref`s `envelope-v2.json` by `$id`** — the bundle never re-declares
  envelope fields, so there is no second envelope dialect.
- **Inline `envelopes[]`, with the disclosure declared.** Spec §4.3 and the
  `AuthorityFactBundle` struct normatively define the bundle as the projection **+**
  the history it was derived from; a URI list would be a different artifact.
  Verification is by re-derivation, not signature (§4.3.1). The method description
  states that the caller receives the signed envelopes, not a summary.
- **Auth `session`, not `admin`.** In this catalog `admin` = "requires an enterprise
  scope"; the projection is an OSS capability (spec + engine landed in OSS). Gating
  it behind an enterprise scope would make a plain OSS deployment unable to expose
  it. `session` matches `rigorix.audit.read/list/summary`.

## Changes

| File | Change |
|---|---|
| `schemas/api/catalog.json` | + `rigorix.audit.authorityFacts`; + `$defs.authorityFactsParams` / `authorityFactsResult` (23 → 24 methods) |
| `schemas/api/authority-fact-bundle.json` | **new** frozen schema — the §4.3 bundle (`projection`, `envelopes[]`, `subjects_without_record`) + `$defs` for the nested shapes + `x-verification` |
| `schemas/api/method-catalog.md`, `schemas/api/README.md`, `schemas/README.md` | reflect the new method/file; method counts 23 → 24 |
| `rust/rigorix-client/src/catalog.rs` | explicit `ServerOnly` binding (no typed wrapper yet) |
| `typescript-client/src/catalog.ts` | `server_only` binding |
| `go/client/catalog.go` | `ServerOnly` binding |
| `java/src/main/java/dev/rigorix/sdk/client/Catalog.java` | `SERVER_ONLY` binding (drift-tested in CI) |
| `go/internal/corpus/corpus_gen.go` | regenerated (`go run ./scripts/gen-corpus`) |
| `rust/rigorix-verifier/src/lib.rs` | register the bundle `$id` as a cross-file resource; compile it in `all_schemas_compile`; add `catalog_declares_authority_fact_projection_additively` |
| `docs/contract-sync-2026-10-13.md` | **new** contract delta note (schema rule 4) |
| `README.md` | status count 23 → 24 + projection line |

The Python/TypeScript `_schemas/` copies are generated (gitignored) from `schemas/`;
the Go corpus is generated. Their sync tests re-derive and compare byte-for-byte.

## Verification

```
cargo test -p rigorix-verifier -p rigorix-client -p rigorix-schemas   ✅
cargo fmt --check                                                     ✅
cargo clippy --all-targets -- -D warnings                             ✅
go test ./...                                                         ✅
python -m pytest                                                      ✅ (19 passed)
npm test   (typescript verifier)                                      ✅ (19 passed)
npm test   (typescript-client)                                        ✅ (10 passed)
mvn -B -q verify   (java)                                             ✅ (incl. catalog drift)
.pi/scripts/validate-ci.sh                                            ✅
.pi/scripts/validate-tests.sh                                         ✅
.pi/scripts/validate-architecture.sh                                  ✅
.pi/scripts/validate-canonical.sh                                     ✅
```

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Canonical catalog carries the method (params, result, auth) | ✅ |
| 2 | Both polyglot copies match the canonical catalog byte-for-byte | ✅ (generated; sync tests) |
| 3 | `rigorix-schemas` embeds the updated catalog | ✅ (`build.rs` + `embedded_corpus_matches_disk`) |
| 4 | rust/ts/go clients + drift test agree on the method set | ✅ |
| 5 | Minor release shipped; notes state the sequencing requirement | ⏳ release-owner action (documented below) |
| 6 | Additive only — old verifiers still verify envelopes | ✅ (no envelope form change) |

## Release sequencing (required follow-up)

A **minor SDK release (0.4.0 → 0.5.0)** must cut before `rigorix-oss`
`ISSUE-PROJECTION-SURFACES` ships its MCP tool, and the release notes MUST state
that consumers upgrade the SDK before the OSS tool ships. Cutting the release is the
release owner's action (registry credentials); it is not part of this contract commit.

## Not in scope

- Implementing the tool in `rigorix-oss` (separate issue, that repo) or enterprise
  ingestion (separate issue).
- A typed client wrapper for the new method (binding is explicit `server_only`).
