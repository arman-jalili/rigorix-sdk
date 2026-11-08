# rigorix-client (TypeScript)

Protocol-only typed client for the frozen `rigorix.*` JSON-RPC catalog
([ADR-0001](../../docs/adr/ADR-0001-native-api-catalog.md)). It mirrors the
catalog `$defs` and speaks JSON-RPC 2.0 over `POST /rpc` (single requests,
batch arrays, notifications).

Two invariants are enforced in code and CI:

- **Governed flows only** — no raw step-execution surface (ADR-0001 D10); a
  test fails if one is ever added.
- **No engine dependency** — execution logic never moves into an SDK (D-1).

## Install

```bash
npm install rigorix-client@0.8.0
```

## Usage

```ts
import { Client, FetchTransport } from "rigorix-client";

const client = new Client(new FetchTransport("https://host/rpc", { authorization: "Bearer …" }));

const plan = await client.plan({ template_name: "attendance" });
const run = await client.run({ template_name: "attendance" });
const version = await client.version(); // checks the apiVersion major constraint

await client.notify("rigorix.audit.read", { execution_id: run.execution_id });
const batch = await client.batchRaw([new BatchCall("rigorix.audit.list", {})]);
```

## Transport seam

Implement `Transport` (`post(body) => response`), or use the built-in
`FetchTransport` (global `fetch`, Node 20+) / `MockTransport` (tests).

## Errors

`errors.json` `data.type` maps to a distinct `ApiError.kind`; an unknown type
falls through to `"unknown"` — never a throw. `JsonRpcError` wraps a JSON-RPC
`error`; `TransportError`/`ProtocolError`/`VersionMismatchError` cover the rest.

## Catalog binding + drift

`catalog.METHODS` lists every frozen method as `typed` or `server_only`.
`catalog_drift` reads `schemas/api/catalog.json` and fails if the two diverge —
the namespace is closed, so no method is silently omitted. Server-only
exemptions: `audit.head`/`.history`/`.overdue` (enterprise Phase B),
`auth.verify` (enterprise JWKS), `policy.bundle` (admin control plane).

## Test

```bash
npm install
npm test          # tsc + node --test
```
