# Implementation Plan: issue/44

**Branch:** `issue/44`
**Base:** `main` (post-#43, `56b0ccd`)
**Issue:** #44 — SDK-CATALOG-PROJECTION-METHOD
**Decision:** surface = MCP/catalog method (approved); contract option 3 (dedicated
schema file) with amendments.

## Status

- [x] Surface decision confirmed (MCP tool, not CLI-only)
- [x] Contract shape confirmed (option 3: standalone `$id` file)
- [x] Canonical catalog updated
- [x] Dedicated bundle schema added
- [x] Polyglot copies + Go corpus regenerated
- [x] Client binding tables (rust/ts/go) updated
- [x] Integrity test + contract delta note added
- [x] All language suites + validators green
- [ ] MR created
- [ ] Merged

## The decision (frozen contract)

| Field | Value |
|---|---|
| method | `rigorix.audit.authorityFacts` |
| kind | `query` |
| auth | `session` (OSS capability; `admin` = enterprise scope) |
| mcpTool | `rigorix_audit_authority_facts` |
| params | `{ subjects: string[] (required), producer_id?: string }` |
| result | `$ref` `https://rigorix.dev/schemas/api/authority-fact-bundle-v1.json` |

Shape decisions recorded in `docs/contract-sync-2026-10-13.md`:
1. Standalone file (`$id`), not inline — like `auditHistoryResult` → `history-slice-v1.json`.
2. `envelopes[]` `$ref`s `envelope-v2.json` by `$id` — no second envelope dialect.
3. **Inline `envelopes[]`** (not URI list): spec §4.3 + the `AuthorityFactBundle`
   struct normatively define the bundle as projection + the history it was derived
   from. Disclosure stated in the method description.
4. Auth `session`, matching `rigorix.audit.read/list/summary`.

## Changes

| File | Change |
|---|---|
| `schemas/api/catalog.json` | + method `rigorix.audit.authorityFacts`; + `$defs.authorityFactsParams`/`authorityFactsResult` (23 → 24) |
| `schemas/api/authority-fact-bundle.json` | **new** frozen schema (§4.3 bundle) |
| `schemas/api/method-catalog.md`, `schemas/api/README.md`, `schemas/README.md` | reflect the new method/file; counts 23 → 24 |
| `rust/rigorix-client/src/catalog.rs` | `ServerOnly` binding |
| `typescript-client/src/catalog.ts` | `server_only` binding |
| `go/client/catalog.go` | `ServerOnly` binding |
| `java/src/main/java/dev/rigorix/sdk/client/Catalog.java` | `SERVER_ONLY` binding |
| `go/internal/corpus/corpus_gen.go` | regenerated (`go run ./scripts/gen-corpus`) |
| `rust/rigorix-verifier/src/lib.rs` | register bundle `$id`; compile it in `all_schemas_compile`; new integrity test |
| `docs/contract-sync-2026-10-13.md` | **new** contract delta note |
| `README.md` | status count 23 → 24 + projection line |
| `_schemas/` copies (python/ts) | regenerated (gitignored) |

## Verification

- `cargo test -p rigorix-verifier -p rigorix-client -p rigorix-schemas` — green
- `go test ./...`, `pytest` (19), `npm test` (ts verifier 19, ts-client 10), `mvn -B -q verify` (java) — green
- `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings` — green
- `validate-ci.sh`, `validate-tests.sh`, `validate-architecture.sh`, `validate-canonical.sh` — green
- Corpus/copy sync tests re-derive from `schemas/` and compare byte-for-byte — green

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Canonical catalog carries the method (params, result, auth) | ✅ |
| 2 | Polyglot copies match byte-for-byte after regeneration | ✅ (generated; sync tests) |
| 3 | `rigorix-schemas` embeds the updated catalog | ✅ (build.rs; `embedded_corpus_matches_disk`) |
| 4 | rust/ts/go clients + drift test agree on the method set | ✅ |
| 5 | Minor release + sequencing note | ⏳ release-owner action (documented) |
| 6 | Additive only — old verifiers still verify envelopes | ✅ |

## Follow-up (not this PR)

Minor SDK release 0.4.0 → 0.5.0; release notes must state consumers upgrade before
`rigorix-oss` `ISSUE-PROJECTION-SURFACES` ships its MCP tool.
