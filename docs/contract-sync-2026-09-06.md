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

- **2026-09-08 (this PR)** — F-20260907-01 rigorix-oss conformance round:
  - `schemas/fixtures/envelope/*.json` — 5 REAL engine-signed envelopes from
    actual rigorix-oss runs (fixed test-only key `fixture-hmac-key-2026`) +
    README documenting the key. Regeneration path documented.
  - **Canonicalization drift found + fixed (both repos):** serde emits
    `HashMap` keys in per-process hash-random iteration order, so
    `canonical_bytes()` was unstable and `verify_signature` failed even
    in-crate once a map-typed field (`scoring_results` / `dimensions`) had >1
    entry. Map-typed envelope fields now serialize with sorted keys
    (identical `serialize_with` helper in rigorix-oss envelope.rs and this
    verifier's frozen copies) — JSON shape unchanged, canonical bytes
    reproducible anywhere. `schemas/envelope.json` description updated.
  - rigorix-verifier fixture test: all committed engine fixtures verify
    byte-exact + validate vs envelope.json v1 (9 tests green).

- **2026-09-19 — catalog freeze (ADR-0001, PR `feat/catalog-freeze`):**
  Contract-sync milestone 1 opened the gate for catalog design. The
  `schemas/api/method-catalog.md` sketch is now realized and **frozen**:
  - `docs/adr/ADR-0001-native-api-catalog.md` — the decisions: JSON-RPC 2.0
    over `POST /rpc`, dot-separated lowerCamelCase `rigorix.*` names, additive-
    only versioning, three auth levels, the **identity invariant** (caller-
    supplied identity is display-only — authorization is the attested session),
    the error taxonomy, the SSE push channel, and the MCP adapter table.
  - `schemas/api/catalog.json` — the catalog **data**: 19 methods, each with
    kind/auth/since/stability + params/result `$ref`s into its `$defs`,
    grounded in rigorix-oss MCP tool descriptors + `*/application/dto`.
  - `schemas/api/catalog.schema.json` — JSON Schema for the catalog document.
  - `schemas/api/errors.json` — the JSON-RPC error model (`data.type` stable;
    `denied_by_sequence` carries `rule_id` + `step`).
  - `schemas/README.md` — resolved the envelope revision ambiguity: the schema
    is **envelope format v2** (`$id` `envelope-v2.json`); "v1" in the prose was
    the schema-document revision. Consumers key on `$id`.
  - `rigorix-verifier`: `catalog_integrity` (schema-conformance + unique names +
    resolvable refs) and `error_taxonomy_codes_consistent` — 12 tests green;
    SDK CI added (fmt · clippy · test).
  - **Next:** `rigorix-server` (OSS reference host) + enterprise execution API
    build against this surface; SDK clients are thin typed clients + verifier.

- **2026-09-19 — ADR-014 effect-identity (additive schema changes):**
  Sequence-policy now expresses the requester-variation class (each step allowed,
  effect identical) without importing domain semantics into the matcher.
  - `schemas/policy.json`: `paramPredicate.kind` gains **`equals_step`** with an
    optional **`step`** (index of an earlier matched step); `value` is now
    optional (defaults ""). `historyPredicate` gains **`effect_key`** (bool,
    default false).
  - `schemas/envelope.json`: gains additive **`effect_key`** (string|null,
    omitted when absent) — a one-way keyed hash, never raw parameters.
  - Engine (rigorix-oss, same PR): `ParamMatchKind::EqualsStep`, relational
    matching over earlier matched steps, `HistoryPredicate.effect_key`, envelope
    field + `HistoryAction.effect_key`, reserved step-parameter pointer
    `/effect_key`, load-time fail-closed validation. Engine 2033 tests green
    (8 new AC tests), conformance green.
  - Both changes are additive and serde-defaulted — existing envelopes/rules
    validate unchanged; an envelope without an effect key never matches an
    effect-keyed rule (GAP-M-12 posture).

- **2026-09-22 — ADR-015 operator step-requirements (additive schema changes):**
  The policy/config surface gains operator-owned single-step obligations that the
  agent-authored plan cannot suppress. Reconciled from rigorix-oss ADR-015 +
  issue #884 code (code is truth): `engine/src/sequence_policy/domain/requirement.rs`
  (`StepRequirement` / `RequirementAction` / `RequirementFinding`),
  `sequence_policy/domain/config.rs` (`SequencePolicyConfig.requirements` + R9
  SafetyCaps), `audit/domain/envelope.rs` (`requirement_findings[]` +
  `RequirementFindingRef`).
  - `schemas/policy.json`: new `$defs.requirementAction` (lowercase
    `deny`/`promote`, default `deny`) + `$defs.stepRequirement`; additive root
    `requirements` array (serde field on `SequencePolicyConfig`); `$defs.safetyCaps`
    gains `max_requirements_per_file` (100) + `max_required_params_per_requirement`
    (16).
  - `schemas/envelope.json`: additive root `requirement_findings[]`
    (serde-defaulted, `skip_serializing_if = Vec::is_empty`, declared struct
    position between `sequence_policy_findings` and `decision_context_ref`) +
    `$defs.requirementFindingRef` (`requirement_id`/`step`/`action`/`unmet`/`summary`).
    Pointer **names** may be recorded; parameter **values** never are (SpanPrivacy).
  - **Drift fixed from code (issue #5 draft contradicted the engine struct):**
    the draft listed `stepRequirement.name` as optional and `action` as required.
    The engine has `name: String` with **no serde default** (required) and
    `#[serde(default)] action: RequirementAction` (optional, defaults `deny`).
    Schema follows the code (required `id`/`name`/`match`).
  - `rust/rigorix-verifier`: focused schema-conformance tests for a requirement-bearing
    policy config and a `requirement_findings` envelope; no frozen-struct change —
    no committed fixture carries `requirement_findings` yet (adding one is the
    follow-up that requires the frozen copy to grow the field).
  - Both changes additive and serde-defaulted — existing envelopes/rules validate
    unchanged; `requirements: []` is the status quo (no gating).

- **2026-09-24 — ADR-0002 SSE push channel (formal spec, additive contract):**
  ADR-0001 D8 fixed the push transport + event-name set but deferred reconnect /
  `Last-Event-ID` semantics and the exact payloads to the servers. ADR-0002
  freezes them before C2/C3 diverge, grounded in the landed OSS reference host
  (`rigorix-oss/server/src/events.rs`, #894) and the engine event enum
  (`engine/src/event_system/domain/event.rs`).
  - `docs/adr/ADR-0002-sse-push-channel.md` — endpoint + SSE framing, monotonic
    u64 `id`, `Last-Event-ID` header/query replay, bounded ring + gap→resync via
    `rigorix.audit.read`, ordering, bounded backpressure, `session` auth +
    per-session scoping (D5 identity invariant), poll fallback, and the normative
    engine `ExecutionEvent` → SSE-name mapping table (24 variants; 5 host-telemetry
    variants explicitly not pushed — none silently dropped).
  - `schemas/api/events.json` — new frozen schema: the three payloads as a `oneOf`
    discriminated union on the SSE `event:` name; `data` `$ref`s
    `envelope.json#/$defs/executionEventRef` (**reuse, no second envelope dialect**)
    and mirrors the OSS `ServerEvent { id, event, data }`. `x-engine-event-mapping`
    carries the mapping table machine-readably.
  - `schemas/fixtures/events/*.json` — one committed fixture per event, each
    validated against `api/events.json` by `rigorix-verifier`.
  - `schemas/api/catalog.json` `transport.push` gains `schema: "api/events.json"`
    (+ `catalog.schema.json`); `catalog_integrity` now resolves the ref and checks
    `push.events` equals the schema discriminants.
  - `rust/rigorix-verifier`: cross-file `$ref` resolution (envelope registered under
    its `$id`, offline, no network); `api/events.json` added to `all_schemas_compile`;
    new `events_fixtures_validate` + `events_mapping_complete` — 16 tests green.
  - **Drift fixed from code (issue #10 draft):** the engine enum has 24 variants
    (the stale `event.rs` doc comment says 11); the 5 audit/telemetry variants are
    not run-lifecycle push and are marked not-pushed.
  - Additive only: a new SSE event name is still a contract change (ADR-0001 D3).

- **2026-09-24 — ADR-016 audit integrity Phase A (additive schema changes):**
  The audit trail gains a local per-producer chain and the contract for
  anchor-signed reads, so interior deletion / reorder / insertion is detectable
  and erasure becomes a recorded compaction. Grounded in rigorix-oss ADR-016 and
  the landed **Phase A** implementation (`83e904ad`, #902): `AuditEnvelope` now
  carries `producer_id` / `sequence` / `prev_hash` / `history_integrity` /
  `history_policy`, and `envelope_hash` is SHA-256 over the **same canonical
  bytes** the HMAC signs (`signature` nulled) — one canonical form, no second
  dialect. The anchor itself (Phases B/C) does not exist yet, so the three
  anchor artifacts are contract-first, frozen from ADR-016's Contract section.
  - `schemas/envelope.json`: additive `producer_id` / `sequence` / `prev_hash` /
    `history_integrity` (`local_unanchored` | `anchored`) / `history_policy`
    (`allow_unanchored`), placed after `evidence_degraded` and before
    `approval_events` to match the engine struct order exactly (canonicalization
    parity). New `$defs.historyIntegrity` / `$defs.historyPolicy`.
    **Drift fixed from code (issue #12 draft):** the draft named only four fields;
    the engine also adds `history_policy` (`HistoryPolicy::AllowUnanchored`) — the
    recorded opt-in that makes the unanchored regime auditable. The schema
    follows the code.
  - `schemas/api/ledger-receipt.json`, `schemas/api/history-slice.json`,
    `schemas/api/compaction-checkpoint.json`: new FROZEN anchor-artifact schemas
    (`{ ledger_id, envelope_hash, sequence, recorded_at, sig }`,
    `{ scope, since, actions[], head_hash, sig }`,
    `{ sequence_from, sequence_to, reason, prior_head, new_head, sig }`). The
    `sig` is Ed25519 over the artifact's canonical JSON with `sig` set to null;
    each schema documents the `x-signing` form. `history-slice` actions mirror
    the engine `HistoryAction` (no parameter values — SpanPrivacy).
  - `schemas/fixtures/integrity/`: `chain.json` + `broken-chain.json` are
    **engine-produced** (fixed key `fixture-hmac-key-2026`, sequences 0..2; the
    broken one deletes the middle envelope); `ledger-receipt.json` /
    `history-slice.json` / `compaction-checkpoint.json` are Ed25519-signed with a
    documented test-only key (regenerated by the ignored
    `generate_anchor_fixtures` test).
  - `rust/rigorix-verifier`: frozen structs gain the ADR-016 chain fields,
    `HistoryIntegrity` / `HistoryPolicy`, and the previously-missing
    `requirement_findings` (so the frozen copy now mirrors the engine struct
    field-for-field); `envelope_hash` (same canonical bytes); `verify_chain`
    (genesis 0 + contiguous sequence + `prev_hash` continuity, legacy
    grandfathered); `verify_chain_with_checkpoints` (accepts a gap iff a valid
    Ed25519-signed checkpoint brackets it, else fails); Ed25519 verification of
    the three anchor artifacts (`ed25519-dalek`). 21 tests green (+1 ignored
    generator); the existing engine fixtures still verify byte-exact.
  - **Verified:** the anchor fixtures also verify under an independent Python
    Ed25519 implementation with the documented public key.
  - Additive and serde-defaulted: pre-Phase-A envelopes validate and canonicalize
    unchanged (legacy = chain-of-one / unknown predecessor, grandfathered).

- **2026-09-24 — SDK-C5 catalog parity (closed namespace; additive contract):**
  The enterprise Execution API (rigorix-enterprise #206 / PR #208) registered
  `rigorix.auth.verify` (`core/src/execution_api/application/catalog.rs:74`,
  dispatch at `:182`) but it was absent from the frozen catalog — drift in a
  namespace meant to be closed (ADR-0001 D3).
  - `schemas/api/catalog.json`: **declared** `rigorix.auth.verify` (query /
    `session` / `mcpTool: null`, `since 1.0.0`) with `$defs.authVerifyParams`
    (`{ attestation: string }`, the enterprise `AttestationParams`) and
    `$defs.authVerifyResult` (`{ claim: identityClaim }` — the enterprise returns
    the full `IdentityClaim`, matching `../claims.json` `$defs.identityClaim`).
    Option (a) from the issue: the org-side JWKS verification is distinct from
    `rigorix.auth.status` (which reports the local session), so declaring wins
    over folding.
  - Added a top-level `description` documenting the **closed namespace** (a
    server implements a subset, never an extension) and allowed it in
    `catalog.schema.json`.
  - `rust/rigorix-verifier`: new `verify_catalog_subset(candidate)` — reads the
    frozen method set and fails on any undeclared `rigorix.*` name
    (`VerifyError::UndeclaredMethod`); `catalog_integrity` now asserts
    `rigorix.auth.verify`'s shape + the closed-namespace description. 23 tests.
  - `schemas/api/README.md` new rule 6 (closed namespace) + `method-catalog.md`
    lists the method with a pointer to `catalog.json` as the authoritative set.
  - **Cross-repo follow-up:** rigorix-oss `server/tests/catalog_parity.rs`
    currently asserts the OSS in-code catalog **equals** the SDK catalog; with
    the closed/subset model it should use the subset guard (the OSS server is a
    subset, not the whole namespace).

- **2026-09-25 — SDK-CATALOG-AUDIT (ADR-016 Phase B surface; additive):**
  The enterprise Execution API (rigorix-enterprise PR #210, merged) registers
  three ADR-016 Phase B ledger methods that the frozen catalog did not declare —
  the same closed-namespace drift SDK-C5 fixed for `rigorix.auth.verify`.
  - `schemas/api/catalog.json`: **declared** `rigorix.audit.head` /
    `.history` / `.overdue` (query / `session` / `mcpTool: null`, `since`
    1.0.0), grounded in `rigorix-enterprise
    core/src/execution_api/application/{catalog,services,dto}.rs`:
    - `auditHeadParams { producer_id }`; `auditHeadResult { producer_id,
      sequence|null, envelope_hash|null, anchor_public_key }` (the adapter's
      head is nullable via null fields and carries the anchor's Ed25519 key).
    - `auditHistoryParams { producer_id, since? }`; `auditHistoryResult`
      **reuses the frozen `api/history-slice.json` by `$id`** (no second
      dialect).
    - `auditOverdueParams { threshold_secs? }`; `auditOverdueResult
      { threshold_secs, count, runs[{ execution_id, status, registered_at }] }`
      (`status` = the `RunStatus` serde snake_case set).
  - `rust/rigorix-verifier`: `build_validator` registers `api/history-slice.json`
    as a cross-file resource; `catalog_integrity` asserts the three methods'
    shape + the history-slice reuse; the closed-namespace subset test now uses
    the enterprise **13-method** set. 25 tests.
  - `schemas/api/method-catalog.md` lists the three methods; contract-sync rule
    4 (integrity test + delta note) satisfied.

- **2026-09-24 — catalog de-duplicates the identity shapes (no instance change):**
  `schemas/api/catalog.json` inlined copies of `claims.json`'s `identityRef`
  (pre-existing) and `identityClaim` (added by SDK-C5). Structurally identical
  but able to drift silently. Both copies removed; the two ref sites now address
  `claims.json` by `$id` — the same cross-file pattern as
  `api/events.json` → `envelope.json`:
  - `validatePlanParams.properties.identity` → `claims.json#/$defs/identityRef`
  - `authVerifyResult.properties.claim` → `claims.json#/$defs/identityClaim`
  - `rust/rigorix-verifier`: `build_validator` now registers `claims.json`
    (beside `envelope.json`) so the catalog's cross-file refs resolve offline;
    new test `catalog_references_claims_shapes_instead_of_duplicating_them`.
    24 tests (+1 ignored).
  - No instance shape changes: a `rigorix.auth.verify` result still carries the
    full `IdentityClaim`.

- **2026-09-25 — SDK-CATALOG-ANCHOR-HEAD / ADR-016 Phase C (additive schema change):**
  rigorix-oss PR #908 (`issue/899`, **still open**) binds a new signed envelope
  field `anchor_head` — the verified anchor ledger head a decision was decided
  against. It was absent from the frozen contract, so all three verifiers
  **dropped it when computing canonical bytes**: an engine-signed **anchored**
  envelope (HMAC over bytes that include the field) recomputed by the verifier
  over bytes that exclude it → `SignatureMismatch`. Anchored evidence — the
  strongest mode — was not independently verifiable, the exact Strategy A
  guarantee ADR-016 exists to provide (and `envelope.json` has no
  `additionalProperties:false`, so schema validation silently tolerated it).
  - `schemas/envelope.json`: additive `anchor_head` (string|null, pattern
    `^[0-9a-f]{64}$`) placed at the engine's exact struct position — after
    `history_policy`, **before `approval_events`** — mirroring
    `engine/src/audit/domain/envelope.rs` (code is truth; the field is bound by
    `envelope_factory_impl.rs::with_anchor` → `runtime.head()`).
  - `schemas/fixtures/envelope/envelope-anchored-signed.json`: an
    **engine-produced** anchored envelope (`history_integrity = anchored`,
    non-null `anchor_head`, `approval_events` non-empty so the position relative
    to them is proven), generated through the REAL anchored factory by
    `RIGORIX_FIXTURE_OUT` + `write_anchored_signed_fixture` on `issue/899` with
    the fixed key `fixture-hmac-key-2026`. The existing corpus was all
    `local_unanchored`/legacy, so the anchored path had no byte-exact coverage.
  - `rust/rigorix-verifier` (`AuditEnvelope` field at the same position + serde
    skip-if-none), `python/rigorix_verifier/canonical.py` and
    `typescript/src/canonical.ts` (skip-none set) gain the field; all three
    parity tests assert the anchored fixture verifies byte-exact and that it is
    signed/tamper-detected; legacy + `local_unanchored` fixtures still verify
    byte-exact (skip-if-none leaves their bytes unchanged).
  - **Cross-repo status:** the field's origin (#908) is not yet merged; the
    contract follows the branch's code, and the fixture was generated from that
    branch, so the SDK validates anchored evidence the moment #908 lands. When
    it merges, no SDK change is needed (the field/position are already frozen).

- **2026-09-25 — SDK-CRATES-0.2.0 (release; no contract change):**
  `rigorix-schemas` 0.1.0 + `rigorix-verifier` 0.1.0 were published **before**
  #31/#32 added `anchor_head`, so the crates.io verifier cannot verify an
  anchored envelope. `rust/Cargo.toml` `[workspace.package] version` is now
  **0.2.0** (and the verifier/client `rigorix-schemas` dep → 0.2.0).
  - `rust/scripts/verify-packaged-crates.sh` + a CI step prove the packaged
    `rigorix-schemas` `.crate` carries `anchor_head` and the anchored fixture,
    and that a clean consumer verifies it with `RIGORIX_SDK_SCHEMAS` unset.
  - `rust/RELEASING.md` documents the publish order (schemas first), the
    post-publish clean-project check, the `rust-v0.2.0` tag, and the mandatory
    0.x consumer bumps (`^0.1` does not match 0.2).
  - **Deferred (credential-gated):** the actual `cargo publish`, the tag, and
    the `rigorix-oss` / `rigorix-enterprise` consumer bumps. `cargo package -p
    rigorix-verifier` becomes runnable once `rigorix-schemas` 0.2.0 is live
    (cargo resolves the exact-version dep against the registry even with
    `--no-verify`). 0.1.0 is not yanked (valid for catalog-only use).
