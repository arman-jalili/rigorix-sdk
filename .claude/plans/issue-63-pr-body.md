## Summary

Closes the gap between the Go client's binding table and its typed surface.
`go/client` already framed JSON-RPC, bound all 24 catalog methods, and
drift-tested the table — but only `Version` had a typed wrapper, and
`types.go` only defined `VersionResult`.

## What changed

- **`types.go`** — DTOs for every typed method, mirroring
  `schemas/api/catalog.json` `$defs` (TS `types.ts` is the field-for-field
  reference). Nullable schema fields are pointers.
- **`methods.go`** — the 18 typed wrappers over the frozen method names:
  plan, validatePlan, run, execute, approve, checkEnforcement, audit.read/list/
  summary, template.list/get/create/validate, auth.login/status/logout,
  usageGuide (+ the existing version).
- **`client.go`** — `CallRaw` captures the generated id and rejects a
  missing/mismatched response id with `ProtocolError` (seed S3); `Version`
  parses `api_version` (accepts `1.0.0` and `v1`) and rejects a major other
  than 1 with `VersionMismatchError` naming the advertised value (seed S4).
- **`error.go`** — `ProtocolError`, `TransportError`, `VersionMismatchError`.
  `RPCError` still carries `code`, `message`, and `data` (seed S1).
- **`transport.go`** — `TransportError` on non-2xx and on an exhausted mock
  queue, so "the host did not answer" is not confused with an RPC refusal.
- **Tests** — table over all 17 non-version methods (asserts the method name on
  the wire), version v1/v2/invalid, id mismatch, invalid JSON, missing result,
  HTTP 200/500 via `httptest`, live `TestLiveVersion` gated on
  `RIGORIX_SERVER_URL`.
- **`go/README.md`** — client usage.

## Surface note (code is truth)

The issue says "the same eight methods" and lists `executeStep`. The current
`typescript-client/src/client.ts` exposes **18** typed methods since
audit/template/auth were added; `executeStep` is **not** in the frozen catalog
and ADR-0001 D10 forbids a raw step-execution surface. Every one of the issue's
named eight is included; no raw step path is added.

## Evidence

```
go test ./client/... -cover     87.6% of statements
go test ./...                   ok (verifier + client)
go vet ./...                    clean
gofmt -l go/client              empty
validate-ci/tests/security/operations/canonical/architecture/integration  PASS
cargo build/test/clippy/fmt     green
```

Refs #63 — close after merge.
