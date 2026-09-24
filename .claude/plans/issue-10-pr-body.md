## Summary

Freezes the SSE push channel (`GET /events`) **before** either server is built
— SDK-C1 / ADR-0002. Closes the reconnect + `Last-Event-ID` + payload gap that
ADR-0001 D8 deliberately left open, so OSS `rigorix-server` (C2) and the
enterprise Execution API (C3) implement one spec instead of diverging.

Grounded in **code truth**, not the issue prose:

- `rigorix-oss/server/src/events.rs` (#894) — `EventKind`, `ServerEvent
  { id, event, data }`, monotonic u64 ids, `Last-Event-ID` header/query, bounded
  replay ring + broadcast, 15 s keep-alive.
- `rigorix-oss/engine/src/event_system/domain/event.rs` — the 24
  `ExecutionEvent` variants + `event_type_name()`.
- `schemas/envelope.json#/$defs/executionEventRef` — the event-ref shape to reuse.

Closes #10.

## Changes

**`docs/adr/ADR-0002-sse-push-channel.md`** (Accepted) — endpoint + SSE framing;
monotonic u64 `id`; `Last-Event-ID` replay with a bounded ring and a
gap→`rigorix.audit.read` resync rule; ordering; bounded backpressure (slow
consumer drops, never stalls execution); `session` auth + per-session scoping
(D5 identity invariant); poll fallback; and the normative
`ExecutionEvent` → SSE-name mapping table.

**`schemas/api/events.json`** (new, FROZEN) — the three payloads as a `oneOf`
discriminated union on the SSE `event:` name. `data` `$ref`s
`envelope.json#/$defs/executionEventRef` (**reuse — no second envelope dialect**)
and mirrors the OSS `ServerEvent { id, event, data }`. `x-engine-event-mapping`
carries the engine→SSE table machine-readably.

**`schemas/fixtures/events/`** (new) — one fixture per event
(`run-progress`, `approval-required`, `policy-changed`) + README.

**`schemas/api/catalog.json` / `catalog.schema.json`** — `transport.push` gains
`schema: "api/events.json"`.

**`rust/rigorix-verifier`** — cross-file `$ref` resolution (envelope registered
under its `$id`, offline, no network); `api/events.json` added to
`all_schemas_compile`; new `events_fixtures_validate` +
`events_mapping_complete`; `catalog_integrity` now resolves `push.schema` and
checks `push.events` equals the schema discriminants.

**Docs** — `schemas/README.md`, `schemas/api/README.md`, and an ADR-0002 delta
note in `docs/contract-sync-2026-09-06.md`.

## Drift found and fixed (code is truth)

- The engine enum has **24** variants; `event.rs`'s doc comment still says "11".
- The 5 audit/telemetry variants (`audit_envelope_*`, `circuit_breaker_state_changed`)
  are host telemetry, **not** run-lifecycle push — the ADR table marks them
  not-pushed explicitly so none is silently dropped (AC 4).
- The pending-approval pause is server state (`pending_approval_steps`), not an
  engine event; the OSS `EventHub` is not yet wired to the engine bus. The
  approval-lifecycle engine events (`approval_recorded`,
  `intent_mismatch_detected`) map to `approval_required`.

## Validation

```
cd rust
cargo build
cargo test --workspace        # 16 passed (was 14)
cargo clippy --all-targets -- -D warnings
cargo fmt --check
cargo audit                   # 0 advisories
```

`.pi/scripts/validate-{ci,tests,security,operations}.sh` → PASS (warnings only;
the `cargo audit` script warning is a heuristic false positive — exit 0, no
advisories).

## Out of scope / follow-ups

- Servers (C2 / C3) implementing the spec; this PR is spec-only.
- OSS `server/src/events.rs` still owes per-session scoping and the `retry:`
  hint, and engine-bus wiring (tracked in ADR-0002 "Open items").
- Changing the frozen SSE event-name set remains a contract change (additive-only
  within `apiVersion` 1.x).
