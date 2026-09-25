# Native API — `rigorix.*` method catalog (draft sketch)

**Status:** sketch only (2026-09-06). Design step comes AFTER contract sync — the catalog
is built *over* synced contracts so it cannot freeze drift. This sketch records the
agreed shape: JSON-RPC 2.0 over HTTP, first-class typed methods, MCP stays an adapter.

> **The live, frozen method set is [`catalog.json`](catalog.json)** (ADR-0001). This
> file is historical context; `rigorix.auth.verify` was declared after the sketch
> (SDK-C5) and is authoritative only in `catalog.json`.

## Shape

- Transport: JSON-RPC 2.0 over HTTP POST (`/rpc`); SSE/event stream for push (approval
  requests, run progress, policy-change notifications).
- Auth at the boundary: local/API-key for OSS reference server; API-key/JWKS + team
  scoping for enterprise execution API.
- Error shape: JSON-RPC error objects with rigorix error taxonomy
  (`EngineFacadeError`/`ProxyError` categories: policy_violation, denied_by_sequence,
  not_authenticated, api_error, timeout...).

## Method sketch (concepts — names not final)

| Method | Concept |
|---|---|
| `rigorix.plan` | intent → plan + enforcement/risk findings (mirrors `rigorix_plan`) |
| `rigorix.validatePlan` | plan validation (mirrors `rigorix_validate_plan`) |
| `rigorix.run` | governed execution of a plan (pause/approve/deny states; mirrors `rigorix_run`) |
| `rigorix.approve` | human approval with binding evidence (mirrors `rigorix_approve_execution`, ADR-011) |
| `rigorix.checkEnforcement` | enforcement state snapshot (mirrors `rigorix_check_enforcement`) |
| `rigorix.audit.list` / `rigorix.audit.read` / `rigorix.audit.summary` | signed trail (envelope v2) |
| `rigorix.auth.login` / `rigorix.auth.status` / `rigorix.auth.logout` | OIDC device flow (RFC 8628, ADR-008/012) |
| `rigorix.auth.verify` | org-side JWKS verification of an OSS-attested claim → the verified identity claim (enterprise Execution API; SDK-C5) |
| `rigorix.template.*` | template CRUD/validate |
| `rigorix.policy.bundle` | policy export for OSS-side enforcement (enterprise: source of truth) |
| `rigorix.usageGuide` | self-description (mirrors `rigorix_get_usage_guide`) |

## Non-goals (frozen)

- No raw engine-step escape hatch in the catalog (governed flows only).
- No legacy MCP SSE endpoint. MCP Streamable HTTP optional later (GUI agents), as an
  adapter over this catalog.
- Enterprise `rigorix_enterprise_*` tools (MCP proxy seam) proxy these methods once the
  enterprise execution API exists — the seam's JSON-RPC assumption becomes true.
