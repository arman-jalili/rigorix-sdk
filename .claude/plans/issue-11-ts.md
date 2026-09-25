# Implementation Plan: issue/11-ts (TypeScript client follow-up)

**Branch:** `issue/11-ts` (stacked on `issue/11` — the Rust client PR #26)
**Base:** `issue/11` → `main` after the stack merges
**Issue:** #11 — SDK-C4 (TypeScript half; follows the Rust client).

## Classification

New deliverable. Scope: **Complex**. Protocol-only; no engine.

## Why a separate dir

`typescript/` is the #21 verifier package; the client lives in
`typescript-client/` (package `rigorix-client`).

## Deliverables

1. `typescript-client/` — `rigorix-client`:
   - `jsonrpc.ts` — request/response framing, batch arrays, notifications.
   - `transport.ts` — `Transport` interface + `FetchTransport` (global fetch) +
     `MockTransport` (tests). Zero runtime dependencies.
   - `error.ts` — `ApiError` kind mapping (all `errors.json` types + `unknown`),
     `JsonRpcError`, `TransportError`, `ProtocolError`, `VersionMismatchError`.
   - `catalog.ts` — the full method binding table (`typed` / `server_only`).
   - `types.ts` — typed params/results mirroring the catalog `$defs`.
   - `client.ts` — `Client` with typed wrappers, batch/notification framing,
     `system.version` negotiation.
   - `auth.ts` — device-flow helpers; `README.md`.
2. Tests: catalog drift, error mapping, framing, version, typed dispatch.
3. CI job `typescript-client`; `.gitignore` `typescript-client/dist/`.

## Validation

- [x] `npm test` (tsc + `node --test`) — **10 tests**
- [x] catalog drift vs `schemas/api/catalog.json`
- [x] error taxonomy: distinct kind per type + `unknown` fallback
- [x] framing: single / notification (no id) / batch (array)
- [x] version negotiation accept/reject

## Status

- [x] Implemented
- [x] Local deterministic checks green
- [ ] MR pushed
- [ ] Merged
