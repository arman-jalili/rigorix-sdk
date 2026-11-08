# Issue #63 — Go protocol client (SDL-1)

**Branch:** `issue/63`
**Component:** `go/client` (inside the existing `go` module; no new module path)
**Priority:** high
**Status:** ready (no external dependency)

## Current state — code is truth

`go/client` already has:

| File | Exists |
|---|---|
| `transport.go` | `Transport`, `HTTPTransport`, `MockTransport` |
| `jsonrpc.go` | `RPCRequest`, `RPCResponse`, `RPCError`, `Call`, `Notification` |
| `client.go` | `CallRaw`, `CallTyped`, `Notify`, `BatchRaw`, `Version` |
| `catalog.go` | all 24 frozen methods bound: 18 `Typed`, 6 `ServerOnly` |
| `catalog_drift_test.go` | set equality with `schemas/api/catalog.json` + no raw step execution |
| `types.go` | **only `VersionResult`** |

Gaps against the issue and the TS reference:

1. The binding table claims 18 methods are `Typed`, but only `Version` has a
   typed wrapper and only `VersionResult` exists.
2. `CallRaw` does not check the response `id` — a mismatched id is accepted as
   an answer (issue seed S3).
3. `Version` does not enforce the `v1` major (issue seed S4).
4. No live test, no HTTP transport test, coverage below the 80 % target.

## Surface — the TS client is the reference

The issue says "eight methods", but `typescript-client/src/client.ts` exposes
**18** typed methods since audit/template/auth were added. All eight the issue
names are in this set. `executeStep` is **not** in the frozen catalog and is
forbidden by ADR-0001 D10; do not add it.

```
plan, validatePlan, run, execute, approve, checkEnforcement,
audit.read, audit.list, audit.summary,
template.list, template.get, template.create, template.validate,
auth.login, auth.status, auth.logout,
usageGuide, version
```

The six `ServerOnly` bindings (audit.head/history/overdue/authorityFacts,
auth.verify, policy.bundle) stay untyped — the TS client does not expose them
either; the binding table already records why.

## Changes

- **`types.go`** — DTOs mirroring `schemas/api/catalog.json` `$defs` (the TS
  `types.ts` is the field-for-field reference): `PlanParams/Result`,
  `Constraints`, `ValidatePlanParams`, `ValidateResult`, `CostEstimate`,
  `RunParams`, `ExecuteParams/Result`, `StepResult`, `ApproveParams/Result`,
  `CheckEnforcementResult`, `BudgetStatus`, `CircuitBreaker`,
  `AuditReadParams/Result`, `AuditListParams/Result`, `AuditListItem`,
  `AuditSummaryParams/Result`, `TopFailure`, `TopTemplate`,
  `TemplateListParams/Result/Item`, `TemplateGetParams/Result`,
  `TemplateCreateParams/Result`, `TemplateValidateParams`,
  `AuthLoginParams/Result`, `AuthStatusResult`, `ClaimSummary`,
  `AuthLogoutResult`, `UsageGuideResult`, `EmptyParams`.
  Nullable schema fields become pointers (`*string`, `*int64`, `*bool`).
- **`methods.go`** — the 18 typed wrappers, each a one-line `CallTyped` over the
  frozen method name. No-arg methods send `EmptyParams{}` (`{}`).
- **`client.go`** — `CallRaw` captures the generated id and rejects a
  missing/mismatched response id with `ProtocolError`; `Version` parses
  `api_version` (accepts `1.0.0` and `v1`) and rejects a major other than 1 with
  `VersionMismatchError`.
- **`error.go`** — `ProtocolError`, `TransportError`, `VersionMismatchError`.
  `RPCError` keeps `code`/`message`/`data` (issue: "the code survives").
- **`transport.go`** — return `TransportError` on non-2xx and on an empty mock
  queue.
- **`methods_test.go`** — table-driven test for all 18 methods (asserts the
  method name on the wire), version `1.0.0`/`v2`, id mismatch, `httptest` HTTP
  success + 500, live `TestLiveVersion` gated on `RIGORIX_SERVER_URL`.
- **`go/README.md`** — a short client section.

## Acceptance mapping

| Issue criterion | Test |
|---|---|
| eight methods exist with typed returns | `TestTypedMethods` (18, superset) |
| catalog parity, none extra | `TestCatalogDrift` (already; 24/24) |
| governed flows only | `TestCatalogDrift` → `AssertNoRawStepExecution` |
| live same DTO as TS | `TestLiveVersion` (`RIGORIX_SERVER_URL`) |
| coverage ≥ 80 % | `go test -cover ./client/...` |
| S1 code preserved | `TestRPCError` (existing) |
| S2 batch success+error survive | `TestBatchFraming` (existing) |
| S3 id mismatch refused | `TestIDMismatch` |
| S4 v2 refused, major in message | `TestVersionRejectsMajor` |

## Validators

```
gofmt -l go/client
go vet ./client/...
go test ./client/... -cover
go test ./...                 # verifier must stay green
cargo build/test/clippy/fmt   # full deterministic gate
guardian validate ci/tests/security/architecture/integration
```

## Notes

- No new dependency: `net/http`, `encoding/json`, `context` only.
- No schema/contract change: the catalog is already frozen at 24 methods.
- `BatchRaw` keeps response order; the issue's S2 only requires both responses
  survive in order. Id matching is enforced on single calls (S3).
