# ADR-0001 — Native API catalog (`rigorix.*`, JSON-RPC 2.0 over HTTP)

- **Status:** Accepted (freeze) — 2026-09-19
- **Context:** rigorix-sdk, contract-sync milestone 1 complete
- **Supersedes:** none
- **Related:** `docs/strategy-freeze-2026-09-06.md` (D-3, D-4, D-5, D-6),
  `schemas/api/method-catalog.md` (draft sketch, now frozen here),
  rigorix-oss ADR-008/011/012 (auth device flow, approval binding, identity
  attestation), rigorix-oss ADR-013 (sequence policy)

## Context

rigorix-oss ships a governed execution engine plus an MCP stdio adapter
(14 OSS tools). The strategy freeze (2026-09-06) decided that server mode
exists in **both** repos on **one** native `rigorix.*` JSON-RPC catalog:
an OSS reference execution host (`rigorix-server`) and an enterprise
execution API (module-in-core), with MCP remaining an *adapter*.

Contract-sync milestone 1 is complete: `schemas/envelope.json`,
`schemas/claims.json`, `schemas/policy.json` are reconciled to code truth,
real engine-signed fixtures exist, and rigorix-oss CI proves byte-exact HMAC
parity via the independent `rigorix-verifier`. That substrate is the
precondition for freezing the API surface.

This ADR freezes the catalog. It is the gate before building either server.

## Decision

### D1 — Transport

- **JSON-RPC 2.0 over HTTP `POST /rpc`**, `Content-Type: application/json`.
- Single requests and JSON-RPC batch arrays are both accepted.
- Requests with no `id` are notifications (no response).
- Server→client push (approval requests, run progress, policy changes) uses a
  **separate event stream** (`GET /events`, SSE). Push is *not* JSON-RPC;
  event payloads reuse the envelope event-ref shape (`envelope.json`).
- HTTP status is always `200` for a well-formed JSON-RPC envelope; protocol
  and application errors travel as JSON-RPC `error` objects (D6).

### D2 — Method naming

`rigorix.*`, dot-separated namespaces, lowerCamelCase final segment:

| Namespace | Methods |
|---|---|
| root | `rigorix.plan`, `rigorix.validatePlan`, `rigorix.run`, `rigorix.execute`, `rigorix.approve`, `rigorix.checkEnforcement` |
| audit | `rigorix.audit.read`, `rigorix.audit.list`, `rigorix.audit.summary` |
| template | `rigorix.template.list`, `rigorix.template.get`, `rigorix.template.create`, `rigorix.template.validate` |
| auth | `rigorix.auth.login`, `rigorix.auth.status`, `rigorix.auth.logout` |
| policy | `rigorix.policy.bundle` (enterprise) |
| system | `rigorix.system.version`, `rigorix.usageGuide` |

Naming is **frozen**: a method is never renamed. A replacement is a new
method; the old one is marked `deprecated` in the catalog and kept until the
next major version.

### D3 — Versioning

- The catalog carries a semantic `apiVersion` (`schemas/api/catalog.json`).
- `rigorix.system.version` reports `{ name, engineVersion, apiVersion,
  schemas[], capabilities[] }` for runtime negotiation.
- Within a major version the surface is **additive only**: new methods and new
  optional fields. Removing a field, changing a type, or tightening a
  requirement is a breaking change requiring a new major.
- `schemas/api/catalog.json` is the catalog **data** document; `schemas/
  api/catalog.schema.json` describes it; params/result schemas live in the
  catalog's `$defs` and reference the static schemas under `schemas/`. They track
  code truth; a change here follows the contract-change rule (delta note +
  drift CI), never a silent edit.

### D4 — Authorization levels

Each method declares one `auth` level. The catalog distinguishes *who may
call* from *which identity the run is bound to* (D5).

| Level | Meaning |
|---|---|
| `public` | No session required (auth handshake, self-description, version). |
| `session` | Requires an attested session for authorization-relevant methods; the execution/history surface. |
| `admin` | Requires an enterprise scope (e.g. policy export). Enterprise-only. |

Set:
- `public`: `rigorix.auth.login`, `rigorix.auth.status`, `rigorix.auth.logout`,
  `rigorix.system.version`, `rigorix.usageGuide`, `rigorix.checkEnforcement`,
  `rigorix.plan`, `rigorix.validatePlan`, `rigorix.template.validate`.
- `session`: `rigorix.run`, `rigorix.execute`, `rigorix.approve`,
  `rigorix.template.list`, `rigorix.template.get`, `rigorix.template.create`,
  `rigorix.audit.read`, `rigorix.audit.list`, `rigorix.audit.summary`.
- `admin`: `rigorix.policy.bundle`.

Methods whose steps declare `require_identity` **refuse at plan time** when no
verified identity is attested, regardless of level (ADR-012 / F-20260907-05).

### D5 — Identity invariant (frozen)

The catalog **never accepts a caller-supplied identity for authorization**.

- `author`, `approver_id`, `authority`, `token_claims_ref` are **display-only**
  and MUST be ignored for any authorization, policy-principal, or audit-binding
  decision.
- The authoritative identity is the **attested session identity** (engine
  `IdentityRef`, source `idp_token`/`local_principal`/`unverified`).
- `rigorix.run`/`rigorix.execute` bind the policy principal to the attested
  subject; `rigorix.approve` binds the approval to the attested subject
  (ADR-011). When auth is configured, an unattested `rigorix.approve` is
  refused.

This is an invariant, not a convention: clients cannot widen their authority by
passing parameters.

### D6 — Error model

JSON-RPC `error { code, message, data }`. `data.type` is the stable machine
identifier; `message` is human text and MAY change. Codes:
standard `-32700/-32600/-32601/-32602/-32603` plus rigorix-specific
(mapped from `EngineFacadeError`/`ProxyError`):

| `data.type` | code | Meaning |
|---|---|---|
| `not_authenticated` | -32001 | No attested session where required. |
| `insufficient_scope` | -32002 | Authenticated but lacking authority. |
| `identity_required` | -32012 | Step requires attested identity; refused at plan time. |
| `denied_by_sequence` | -32010 | Sequence policy refused the plan (R2/R7…). |
| `policy_violation` | -32010 | Other policy denial. |
| `approval_required` | -32011 | Run paused for human approval. |
| `budget_exhausted` | -32020 | Budget refuses the run pre-execution. |
| `timeout` | -32021 | Execution/validation timed out. |
| `not_enabled` | -32031 | Feature/capability disabled. |
| `api_error` | -32030 | Upstream/enterprise API error. |
| `internal_error` | -32099 | Unclassified internal error. |

`denied_by_sequence` MUST carry `data.rule_id` and `data.step` when known
(the demo's R2/R7 denials are asserted on these).

### D7 — Idempotency

`rigorix.run`/`rigorix.execute` accept an optional `execution_id` (UUID).
Re-issuing with the same `execution_id` addresses the same durable execution
record; the server is not required to re-run completed work.

### D8 — Push channel

`GET /events` (SSE) emits `approval_required`, `run_progress`, and
`policy_changed` events. Payloads reuse `envelope.json` event refs
(`event_type`, `status`, `payload.step_name`, …). A client that cannot hold a
stream polls `rigorix.audit.read` instead. MCP Streamable HTTP, if added
later, is an adapter over this same catalog/push surface — the legacy MCP SSE
endpoint is **not** resurrected (GAP-A-10).

### D9 — MCP relationship (adapter table)

MCP stays an adapter. Every catalog method with an MCP counterpart maps 1:1;
server-only methods (none today except enterprise `rigorix.policy.bundle`) must
still be expressible by an MCP tool if a client needs them.

| Catalog method | MCP tool |
|---|---|
| `rigorix.plan` | `rigorix_plan` |
| `rigorix.validatePlan` | `rigorix_validate_plan` |
| `rigorix.run` | `rigorix_run` |
| `rigorix.execute` | `rigorix_execute` |
| `rigorix.approve` | `rigorix_approve_execution` |
| `rigorix.checkEnforcement` | `rigorix_check_enforcement` |
| `rigorix.audit.read` | `rigorix_read_audit` |
| `rigorix.audit.list` | `rigorix_list_audits` |
| `rigorix.audit.summary` | `rigorix_audit_summary` |
| `rigorix.template.list` | `rigorix_list_templates` |
| `rigorix.template.get` | `rigorix_get_template` |
| `rigorix.template.create` | `rigorix_create_template` |
| `rigorix.template.validate` | `rigorix_validate_template` |
| `rigorix.usageGuide` | `rigorix_get_usage_guide` |
| `rigorix.auth.login` | `rigorix_auth_login` |
| `rigorix.auth.status` | `rigorix_auth_status` |
| `rigorix.auth.logout` | `rigorix_auth_logout` |
| `rigorix.policy.bundle` | (enterprise; surfaced via `rigorix_enterprise_call`) |
| `rigorix.system.version` | (server-only; capability discovery) |

### D10 — Non-goals (frozen)

- No raw engine-step escape hatch in the catalog — **governed flows only**
  (strategy D-6). Embedded/unmediated execution stays Rust-only via
  `rigorix-engine`.
- No legacy MCP SSE endpoint.
- No unauthenticated policy mutation; policy is exportable (`policy.bundle`)
  and (enterprise) managed through the control plane, never through a run.

## Envelope versioning (resolved)

`schemas/envelope.json` describes the **envelope format v2** (the format that
carries the additive approval / identity / sequence-policy findings blocks).
Its `$id` is `https://rigorix.eu/schemas/envelope-v2.json` and its title is
"Rigorix Audit Envelope v2". The `description` string's "v1 (2026-09-07)" refers
to the **schema-document revision**, not the format. The catalog's
`rigorix.audit.read` result and the push-channel payloads reference this
document. Consumers MUST key on `$id`, not on prose.

## Consequences

- `rigorix-server` (OSS) and the enterprise execution API can be built against
  a frozen surface without inventing names or shapes.
- SDK clients (`rust/`, `python/`, `typescript/`, …) are thin typed clients +
  the protocol-only `rigorix-verifier`.
- The identity invariant (D5) makes the security property independent of every
  future client implementation.
- Adding a method is a contract change: catalog entry + params/result schema +
  integrity test + (if it has an MCP counterpart) the adapter row.

## Open items (tracked, not blocking the freeze)

- `rigorix.template.create` is `session` here; the enterprise catalog will add
  an `admin` variant for org-scoped templates.
- The push channel's exact SSE event-name set is fixed, but the reconnect/`Last-
  Event-ID` semantics are left to the server implementations and will be
  specified when `rigorix-server` lands.
