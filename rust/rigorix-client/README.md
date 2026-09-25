# rigorix-client

Protocol-only typed client for the frozen `rigorix.*` JSON-RPC catalog
([ADR-0001](../../docs/adr/ADR-0001-native-api-catalog.md)). It mirrors the
catalog `$defs` and speaks JSON-RPC 2.0 over `POST /rpc` (single requests,
batch arrays, notifications).

Two invariants are enforced in code and CI:

- **Governed flows only** — there is no raw step-execution surface (ADR-0001
  D10); a test fails if one is ever added.
- **No `rigorix-engine` dependency** (D-1) — execution logic never moves into an
  SDK.

## Usage

```rust
use rigorix_client::{Client, transport::Transport};
use rigorix_client::types::{PlanParams, RunParams};

// Implement `Transport` for your HTTP client (e.g. reqwest).
let client = Client::new(my_http_transport);

let plan = client.plan(&PlanParams { template_name: "attendance".into() })?;
let run  = client.run(&RunParams {
    template_name: "attendance".into(),
    execution_id: None,
    repository: None,
    author: None,
})?;
let version = client.version()?;   // checks the apiVersion major constraint

// Batch + notifications:
let responses = client.batch_raw(&[BatchCall::new("rigorix.audit.list", json!({}))])?;
client.notify("rigorix.audit.read", &AuditReadParams { execution_id: id, format: None })?;
# Ok::<(), rigorix_client::ClientError>(())
```

## Transport seam

The crate depends on no HTTP framework. Implement
`rigorix_client::transport::Transport` (a single `post(body) -> response`), or
use the test `MockTransport`.

## Errors

`errors.json` `data.type` maps to a distinct `ApiError` variant
(`ApiError::from_type`); an unknown type falls through to `ApiError::Unknown`
— never a panic. `rigorix_client::ClientError` wraps transport/JSON/protocol
failures and the typed RPC error.

## Catalog binding + drift

`rigorix_client::catalog::METHODS` lists every frozen method as either
`Binding::Typed` or `Binding::ServerOnly(reason)`. The `catalog_drift` test
reads `schemas/api/catalog.json` (embedded via `rigorix-schemas`, a
dev-dependency) and fails if the two ever diverge — the namespace is closed, so
no method is silently omitted.

Server-only exemptions: `rigorix.audit.head`/`.history`/`.overdue`
(enterprise ADR-016 Phase B), `rigorix.auth.verify` (enterprise JWKS),
`rigorix.policy.bundle` (admin/enterprise control plane).

## Test

```bash
cd rust
cargo test -p rigorix-client
cargo tree -p rigorix-client | grep -c rigorix-engine   # must be 0
```
