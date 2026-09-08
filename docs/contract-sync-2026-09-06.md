# Contract Sync — Design (2026-09-06)

**Status:** Design doc (freeze). Owner: rigorix-sdk `schemas/` + both repos' CI.
**Problem:** rigorix-enterprise lags rigorix-oss by several releases of *shared
contracts*. Server mode cannot be designed or built on drifting contracts.

## Why sync is milestone 1 (not an open-ended catch-up)

Enterprise **never enforces locally** (strategic role, decisions.md D-005: OSS = trust
layer, Enterprise = operational layer). So sync ≠ porting engine features. Sync = making
the three contract surfaces enterprise consumes/produces match what OSS signs/enforces
today, proven by conformance tests — and it is a hard prerequisite of the execution-API
module (milestone 1 of the server plan). Done-criteria: conformance tests green both
directions + enterprise `log.md` reconciled.

## Contract 1 — Audit envelope v2

**OSS reality today** (`engine/src/audit/domain/envelope.rs`): execution_id, timestamp,
template_id, planning_hash, source?, repository?, author?, `identity?` (IdentityRef:
subject/issuer/source[idp_token|local_principal|unverified]/authority?/expires_at? —
redacted, never the raw token), total_tokens, duration_ms, git_commit?, git_branch?,
model_version?, planning_prompt? (opt-in), file_paths[], events[] (ExecutionEventRef:
event_type/summary/occurred_at/correlation_id?/status/payload?), scoring_results{},
signature? (HMAC), **evidence_degraded** (explicit unsigned marker, GAP-M-12),
**approval_events[]** (ADR-011 R3), **scope_violations[]** (R5), **sequence_policy_findings[]**
(R6 — matched rules / dispatch denies; redacted summaries), decision-context ref.

**Enterprise lag:** `audit_ingestion` verifies HMAC + dedups + stores, but its model may
not surface the additive v2 blocks (approval/identity/sequence findings/node events) for
querying/analytics.

**Sync:** real OSS envelope fixture (conference-demo `.rigorix/audit`, key `rgx_live`) →
enterprise ingest → stored, re-verifiable, queryable. Fixture lives here (`schemas/fixtures/`).

## Contract 2 — Policy/config model

**OSS reality today:** `rigorix.toml` / `.rigorix` enforcement config: permission modes,
tool policies, budgets/safety caps, plus `.rigorix/sequence-policy.toml` rules
(step-match, deny/promote actions, `history = { prior_node, same_principal, window_secs }`
— R7), approval binding (ADR-011), identity requirement (ADR-012). **R7 is recent
(#871/#872)** — enterprise has none of this.

**Enterprise lag:** `policy_engine` bundle export + its rule-mapping table
(tool_blocklist/risk_threshold/llm_budget/repository_allowlist/author_allowlist/
template_allowlist) predates sequence rules, approval binding, identity requirement.
Its own finding F-20260904-04: the ENT↔OSS policy-transfer seam is unclosed **both
directions**. F-20260904-01 (Critical): policy CRUD has no role gate — any team member
can loosen the rules gating their own executions.

**Sync:** export schema aligned with what OSS `EnforcementConfig` actually consumes +
sequence/approval/identity policy types; conformance test: exported bundle → OSS engine
enforces **identically** to local config. Trust gate first: `require_scope(WritePolicies)`
(admin) on policy mutations (F-01).

## Contract 3 — Identity/claim format (ADR-012)

**OSS reality:** OIDC device-flow attestation (mcp auth module, Keycloak demo); envelopes
carry the redacted `IdentityRef`; claims forwarded to enterprise with tool calls for
JWKS verification + authorization (authorize half of the OSS-attests/Enterprise-authorizes
seam). Claim summary shape in `mcp/src/auth/domain/value.rs` (`ClaimSummary`).

**Enterprise lag:** must verify the claims OSS actually attests (issuer/client_id/sub/
expiry; JWKS) and scope them to teams/roles.

**Sync:** claim schema; conformance test: OSS-issued claim → enterprise authorizes.

## Trust gate + bookkeeping

1. **F-20260904-01** (policy CRUD role-gating) — precondition for an execution API.
2. **log.md reconciliation** — close F-20260904-05/06/07 (verified fixed in OSS: approval
   binding ADR-011, identity ADR-012, runtime wiring + 1.4.0); F-01/02/03/04 remain open
   and fold into this milestone; add 2026-09-06 entries (this decision + status file).

## Definition of done (milestone 1)

- [ ] `schemas/envelope.json` v2 completed from OSS code (delta map vs enterprise model done)
- [ ] `schemas/policy.json` (enforcement config + sequence rules + approval/identity requirements)
- [ ] `schemas/claims.json` (attested claim + `ClaimSummary`)
- [ ] `schemas/fixtures/` real envelopes + exported bundle + claim samples
- [ ] Conformance tests green in rigorix-oss CI, rigorix-enterprise CI (fixtures pulled in)
- [ ] F-20260904-01 fixed + tested (admin 200 / member 403)
- [ ] `log.md` reconciled (05/06/07 closed; 01–04 tracked in this milestone)

Then: catalog design → servers → SDKs.

## Progress log

- **2026-09-07 (commit `d7f4e3e`)** — milestone-1 sync-by-doing round 2:
  - `schemas/envelope.json` **v0 → v1** full reconciliation vs
    `engine/src/audit/domain/envelope.rs` + `identity/domain/claim.rs`.
    Drift fixed: EventStatus serde values (v0 wrongly said lowercase
    success/failure; code emits `Success|Failure|Skipped|Cancelled` — no
    rename_all), `decision_context` field renamed to `decision_context_ref`
    (`Option<String>`, was object), placeholder `$defs`
    (approvalRecordRef/scopeViolationRef/sequencePolicyFindingRef) and vague
    `scoring_results` completed from their structs. HMAC canonicalization
    contract documented (engine `compute_signature`: SHA-256-HMAC over
    `to_string(envelope with signature=None)`).
  - `schemas/claims.json` **v1** — IdentityClaim (root) + IdentityRef
    ($defs) grounded in `identity/domain/claim.rs`; all Option fields
    required-but-nullable (engine has no skips on IdentityClaim).
  - `schemas/policy.json` **v1** — sequence-policy rule model (SequenceRule,
    StepPredicate, ParamPredicate, HistoryPredicate incl. R7, RuleAction,
    SafetyCaps) + root-config surface.
  - `rust/rigorix-verifier` — protocol-only verifier crate (8 tests: sign/
    verify roundtrip, tamper, GAP-M-12 unsigned policy, wrong key, canonical
    stability, schema conformance, casing rejection). No rigorix-engine dep.
  - Next: real-engine signed fixtures (F-20260907-01, rigorix-oss); delta map
    + additive storage (F-20260907-03, rigorix-enterprise).
