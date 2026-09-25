## Summary

The **TypeScript half** of SDK-C4: a protocol-only typed client for the frozen
`rigorix.*` JSON-RPC catalog, matching the Rust client (#26) surface. Governed
flows only; no raw step execution; no engine dependency.

Part of #11 (follow-up to the Rust client PR #26). **Stacked on #26** (base
branch `issue/11`). Lives in `typescript-client/` because `typescript/` is the
#21 verifier package.

## Changes

**`typescript-client/`** (package `rigorix-client`, zero runtime deps)
- `jsonrpc.ts` — request/response framing, batch arrays, notifications.
- `transport.ts` — `Transport` + `FetchTransport` (global fetch, Node 20+) +
  `MockTransport`.
- `error.ts` — `ApiError.kind` maps every `errors.json` type to a distinct
  value; unknown → `"unknown"` (never throws); `JsonRpcError` /
  `TransportError` / `ProtocolError` / `VersionMismatchError`.
- `catalog.ts` — the full method binding table (`typed` / `server_only`).
- `types.ts` — typed params/results mirroring the catalog `$defs`.
- `client.ts` — `Client` with typed wrappers, batch/notification framing,
  `system.version` negotiation; `auth.ts` device-flow helpers; `README.md`.

**CI** — `typescript-client` job (`npm ci && npm test`); `.gitignore`
`typescript-client/dist/`.

## Catalog drift

`catalog.test.ts` reads `schemas/api/catalog.json` and asserts the client
binding table mirrors it exactly — every method is typed or explicitly
server-only (`audit.head`/`.history`/`.overdue`, `auth.verify`,
`policy.bundle`). A raw step-execution method is impossible by construction and
asserted against.

## Verification

```
cd typescript-client
npm install
npm test          # tsc + node --test -> 10 tests
```

Covered: single-call framing + typed result, notification has no `id`, batch is
one JSON array, RPC error → typed `denied_by_sequence`, version
accept/reject, protocol error, catalog drift, full error-taxonomy mapping.

## Acceptance criteria (TypeScript half)

| # | Criterion | Status |
|---|-----------|--------|
| 2 | TS client builds (`tsc`) and tests pass | ✅ 10 tests |
| 3 | Drift test: every method bound or exempted | ✅ |
| 4 | Error taxonomy maps every type; unknown generic | ✅ |
| 5 | Batch + notification framing tested | ✅ |
| 6 | `system.version` negotiation | ✅ |
| 8 | No raw step-execution surface | ✅ |
| 9 | CI green | ✅ new job |

## Deferred

- Live e2e against C2 `rigorix-server` (env-gated) — the transport seam is ready.

## Out of scope

- The Rust client (#26), the verifier crates (#18/#19), the multi-language
  verifiers (#21).
