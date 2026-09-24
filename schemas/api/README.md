# `schemas/api/` — native API contracts (FROZEN v1)

The frozen contract surface for the native `rigorix.*` API. Decisions are
recorded in [`docs/adr/ADR-0001-native-api-catalog.md`](../../docs/adr/ADR-0001-native-api-catalog.md).

| File | What |
|---|---|
| `catalog.json` | The frozen method catalog **data**: names, kind, auth level, params/result schema refs (`$defs`), MCP adapter mapping. |
| `catalog.schema.json` | JSON Schema describing `catalog.json` (structure + ref pattern). |
| `errors.json` | The JSON-RPC error model: stable `data.type` identifiers and their codes. |
| `events.json` | The SSE push channel (`GET /events`): the three ADR-0001 D8 payloads as a discriminated union on the `event:` name, reusing `envelope.json` event refs. Specified by `docs/adr/ADR-0002-sse-push-channel.md`. |
| `ledger-receipt.json` | ADR-016 anchor-signed ledger receipt (`ledger_id`, `envelope_hash`, `sequence`, `recorded_at`, Ed25519 `sig`). |
| `history-slice.json` | ADR-016 anchor-signed history projection (`scope`, `since`, `actions[]`, `head_hash`, Ed25519 `sig`) the guard consumes in `anchored` mode. |
| `compaction-checkpoint.json` | ADR-016 anchor-signed compaction proof (`sequence_from`, `sequence_to`, `reason`, `prior_head`, `new_head`, Ed25519 `sig`); a verifier accepts a chain gap iff covered by a valid checkpoint. |
| `method-catalog.md` | The 2026-09-06 pre-freeze sketch (historical; superseded by `catalog.json`). |

## Rules

1. **Additive only within `apiVersion` major (ADR-0001 D3).** New methods and
   new optional fields only. Removing a field, changing a type, or tightening a
   requirement is a new major.
2. **Never rename a method (ADR-0001 D2).** A replacement is a new method; the
   old one is marked `deprecated` and kept until the next major.
3. **Identity is session-derived (ADR-0001 D5).** No method accepts a
   caller-supplied identity for authorization. `author` / `approver_id` /
   `authority` / `token_claims_ref` are display-only.
4. **Contract changes are decisions.** A change here always comes with an
   integrity test and a delta note in `docs/contract-sync-*.md`; never a silent
   edit. `cargo test -p rigorix-verifier` guards catalog well-formedness and
   ref resolution.
5. **Code is truth.** Result/param shapes are projections of rigorix-oss DTOs
   (`mcp/src/*/application/dto`); the canonical signed artifact remains
   [`../envelope.json`](../envelope.json), claims [`../claims.json`](../claims.json),
   policy [`../policy.json`](../policy.json). Push payloads reuse
   `envelope.json` event refs — never a second envelope dialect
   ([`events.json`](events.json), ADR-0002).

## Adding a method

1. Add the `$defs` for its params + result in `catalog.json`.
2. Add the method entry (name, kind, since, stability, auth, `mcpTool`, refs).
3. Add the MCP adapter row in ADR-0001 D9 if an MCP counterpart exists.
4. Run `cargo test -p rigorix-verifier` — the integrity test fails on duplicate
   names, dangling `$ref`s, unknown auth levels, or a non-semver `since`.
5. Append a delta note to `docs/contract-sync-*.md`.
