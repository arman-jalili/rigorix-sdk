//! rigorix-verifier — protocol-only verification of Rigorix audit envelopes.
//!
//! Strategy A (SDK freeze D-2): the HMAC trail must be independently
//! checkable anywhere — this crate verifies envelopes WITHOUT depending on
//! rigorix-engine. The envelope structs below are FROZEN copies of
//! rigorix-oss `engine/src/audit/domain/envelope.rs` + the redacted identity
//! ref from `identity/domain/claim.rs` (contract freeze: do not edit them to
//! match engine internals; edit them only when the SDK schemas change).
//!
//! @canonical schemas/envelope.json (Rigorix Audit Envelope v2) — the contract
//! this verifier checks against; the frozen structs below mirror rigorix-oss
//! `engine/src/audit/domain/envelope.rs`.
//!
//! Canonicalization contract (must reproduce the engine byte-exact):
//! HMAC-SHA256 over `serde_json::to_string(envelope with signature = None)`.
//! Struct field order is declaration order; Options with `skip_serializing_if`
//! are omitted when None; Options without it serialize as `null`; empty
//! vectors/maps with `skip_serializing_if` are omitted. The signature field is
//! NOT skipped — canonical bytes include `"signature": null`.

use std::collections::HashMap;
use std::path::Path;

use chrono::{DateTime, Utc};
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// Deterministic map serialization (mirrors rigorix-oss envelope.rs).
///
/// Envelope maps MUST serialize byte-identically on every process for the
/// HMAC canonical form to be reproducible. `std::collections::HashMap`
/// iteration order is hash-randomized per process, so maps are emitted with
/// sorted keys (JSON object key order is not semantic — shape unchanged).
mod sorted_map {
    use serde::Serialize;
    use std::collections::BTreeMap;

    pub fn serialize<S, K, V>(
        value: &std::collections::HashMap<K, V>,
        serializer: S,
    ) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
        K: Ord + serde::Serialize,
        V: serde::Serialize,
    {
        let ordered: BTreeMap<&K, &V> = value.iter().collect();
        ordered.serialize(serializer)
    }
}

/// JSON Schema conformance failure.
#[derive(Debug, thiserror::Error)]
pub enum VerifyError {
    #[error("envelope parse failed: {0}")]
    Parse(#[from] serde_json::Error),
    #[error("schema read failed: {0}")]
    SchemaRead(String),
    #[error("schema validation failed: {0}")]
    Schema(String),
    #[error("signature field is null")]
    MissingSignature,
    #[error("signature mismatch: expected {expected}, got {got}")]
    SignatureMismatch { expected: String, got: String },
    #[error("unsigned envelope without evidence_degraded=true (GAP-M-12 violation)")]
    UnsignedNotDegraded,
    #[error("HMAC key error: {0}")]
    HmacKey(String),
    #[error("audit chain broken: {detail}")]
    ChainBroken { detail: String },
    #[error("invalid Ed25519 anchor signature: {0}")]
    AnchorSignature(String),
    #[error(
        "method `{0}` is not declared in the frozen rigorix.* catalog \
         (ADR-0001 D3 — the namespace is closed; a server implements a subset)"
    )]
    UndeclaredMethod(String),
    #[error("effect record invariant violated: {detail}")]
    EffectInvariant { detail: String },
    #[error("settlement evidence has no readback bytes to verify")]
    ReadbackMissing,
    #[error("readback digest mismatch: expected {expected}, got {got}")]
    ReadbackDigestMismatch { expected: String, got: String },
}

pub type VerifyResult<T> = Result<T, VerifyError>;

type HmacSha256 = Hmac<Sha256>;

// ─── Frozen envelope structs (mirror rigorix-oss envelope.rs) ───────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEnvelope {
    pub execution_id: uuid::Uuid,
    pub timestamp: DateTime<Utc>,
    pub template_id: String,
    pub planning_hash: String,
    pub source: Option<String>,
    pub repository: Option<String>,
    pub author: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub identity: Option<IdentityRef>,
    /// ADR-014: domain-supplied canonical effect key (one-way keyed hash).
    /// Serde-defaulted, omitted when absent — canonical bytes unchanged for
    /// effect-less envelopes. MUST stay in the engine's struct position
    /// (after `identity`, before `total_tokens`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub effect_key: Option<String>,
    pub total_tokens: u32,
    pub duration_ms: u64,
    pub git_commit: Option<String>,
    pub git_branch: Option<String>,
    pub model_version: Option<String>,
    pub planning_prompt: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub file_paths: Vec<String>,
    pub events: Vec<ExecutionEventRef>,
    #[serde(
        default,
        skip_serializing_if = "HashMap::is_empty",
        serialize_with = "sorted_map::serialize"
    )]
    pub scoring_results: HashMap<String, ScoringResultRef>,
    pub signature: Option<String>,
    #[serde(default)]
    pub evidence_degraded: bool,
    /// ADR-016 / GAP-A-30 (Phase A): the chain this envelope belongs to.
    /// Additive and serde-defaulted; `None` in legacy (pre-chain) envelopes.
    /// MUST stay in the engine's struct position (after `evidence_degraded`,
    /// before `approval_events`) or canonical bytes diverge.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub producer_id: Option<String>,
    /// ADR-016: monotonic per-producer sequence (genesis 0). Serde-defaulted.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sequence: Option<u64>,
    /// ADR-016: SHA-256 of the predecessor's canonical bytes (`signature`
    /// nulled — the SAME form the HMAC signs). `None` for genesis/legacy.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prev_hash: Option<String>,
    /// ADR-016: which integrity regime produced this evidence.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub history_integrity: Option<HistoryIntegrity>,
    /// ADR-016: the recorded `allow_unanchored` opt-in, when present. Adds to
    /// the signed bytes, so the regime is auditable.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub history_policy: Option<HistoryPolicy>,
    /// ADR-016 Phase C: the **verified** anchor ledger head this evidence was
    /// decided against — `Some` only in `anchored` mode, bound into the signed
    /// bytes so an auditor can prove which ledger state a decision used.
    /// MUST stay in the engine's struct position (after `history_policy`,
    /// before `approval_events`) or canonical bytes diverge.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub anchor_head: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub approval_events: Vec<ApprovalRecordRef>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub scope_violations: Vec<ScopeViolationRef>,
    /// #1189: whether the R5 scope check actually ran. `None` on legacy
    /// envelopes. MUST stay in the engine's struct position (after
    /// `scope_violations`, before `sequence_policy_findings`) or canonical
    /// bytes diverge; 0.8.0 omitted the field, which made every envelope
    /// carrying it fail verification (#1222).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scope_check: Option<ScopeCheckStatus>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub sequence_policy_findings: Vec<SequencePolicyFindingRef>,
    /// R9/ADR-015 operator step-requirement findings. MUST stay after
    /// `sequence_policy_findings` and before `decision_context_ref`.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub requirement_findings: Vec<RequirementFindingRef>,
    /// ADR-017 R1/B dispatch-time precondition findings. MUST stay after
    /// `requirement_findings` and before `decision_context_ref`.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub precondition_findings: Vec<PreconditionFindingRef>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub decision_context_ref: Option<String>,
}

/// Whether the R5 effect-scope check ran, separate from what it found (#1189).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ScopeCheckStatus {
    Checked,
    NotDeclared,
    Unavailable,
}

/// ADR-016: which integrity regime produced an envelope's evidence.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HistoryIntegrity {
    /// Local cache only — tamper-evident, not anchor-authenticated.
    LocalUnanchored,
    /// Anchor-authenticated evidence (Phase C).
    Anchored,
    /// Anchor configured in anchored mode but no verified head exists yet
    /// (startup window). Not anchor-authenticated; never treat as `Anchored`.
    AnchoredPending,
}

/// ADR-016: a recorded history-policy opt-in.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HistoryPolicy {
    /// Accept best-effort evaluation over `local_unanchored` history.
    AllowUnanchored,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IdentityRef {
    pub subject: String,
    pub issuer: String,
    pub source: IdentitySource,
    pub authority: Option<String>,
    pub expires_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum IdentitySource {
    IdpToken,
    LocalPrincipal,
    Unverified,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionEventRef {
    pub event_type: String,
    pub summary: String,
    pub occurred_at: DateTime<Utc>,
    pub correlation_id: Option<uuid::Uuid>,
    pub status: EventStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub payload: Option<serde_json::Value>,
}

/// EventStatus mirrors the engine enum EXACTLY — including the absence of
/// `rename_all`: serde emits the capitalized variant names
/// (`Success`, `Failure`, `Skipped`, `Cancelled`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum EventStatus {
    Success,
    Failure,
    Skipped,
    Cancelled,
}

/// How an approval's `intent_hash` came to exist (#1243).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum IntentHashProvenance {
    /// The re-deriving engine computed it from the sealed graph (RS-011).
    Derived,
    /// A caller asserted it; the attestation covers who said it, not the graph.
    Asserted,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApprovalRecordRef {
    pub node_id: uuid::Uuid,
    pub step_name: String,
    pub intent_hash: String,
    /// Required: a verifier can distinguish RS-011 binding from RS-013
    /// attribution. The field sits after `intent_hash` in the signed bytes.
    pub intent_hash_provenance: IntentHashProvenance,
    pub approver_id: String,
    pub authority: Option<String>,
    pub decided_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScopeViolationRef {
    pub node_id: uuid::Uuid,
    pub step_name: String,
    pub out_of_scope: Vec<String>,
    pub detected_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SequencePolicyFindingRef {
    pub rule_id: String,
    pub action: String,
    pub later_step: String,
    pub matched_indices: Vec<usize>,
    pub summary: String,
}

/// R9/ADR-015 redacted operator step-requirement finding (mirrors the engine
/// `RequirementFindingRef`). Parameter VALUES never appear (SpanPrivacy).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequirementFindingRef {
    pub requirement_id: String,
    pub step: String,
    pub action: String,
    pub unmet: Vec<String>,
    pub summary: String,
}

/// ADR-017 R1/B dispatch-time precondition finding (mirrors the engine
/// `PreconditionFindingRef`). Fixed shape: `exit_code` is always serialized
/// (`null` for `error`/`unarmed`). Only an `inputs_hash` is recorded \u2014 never
/// parameter values or raw stdout (SpanPrivacy).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreconditionFindingRef {
    pub precondition_id: String,
    pub step: String,
    pub outcome: String,
    pub exit_code: Option<i32>,
    pub inputs_hash: String,
    pub checked_at: DateTime<Utc>,
    pub summary: String,
    /// ADR-017 attribution (#987): SHA-256 of the resolved check program.
    /// Additive/omitted when absent (pre-attribution envelope).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub check_digest: Option<String>,
    /// ADR-017 attribution (#987): SHA-256 of the authority artifact the check
    /// consulted. A changed authority changes this digest.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub authority_digest: Option<String>,
    /// ADR-017 boundary fact (#986): the check was writable by the engine euid.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub check_writable: Option<bool>,
    /// ISSUE-ATTRIBUTION-ABSENCE-REASON: structured reason the attribution
    /// digests are present or absent (`recorded` | `refused_before_check` |
    /// `artifact_unreadable`). Additive/omitted when absent (pre-attribution
    /// envelope); a new engine always sets it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub attribution: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScoringResultRef {
    pub passed: bool,
    pub backend: String,
    #[serde(serialize_with = "sorted_map::serialize")]
    pub dimensions: HashMap<String, ScoreDimensionRef>,
    pub duration_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScoreDimensionRef {
    pub score: f64,
    pub max: f64,
    pub label: String,
    pub passed: bool,
}

// ─── Verification ────────────────────────────────────────────────────────────

/// Compute the canonical envelope bytes: parse, null the signature, serialize
/// exactly as the engine's `compute_signature` does.
pub fn canonical_bytes(json: &str) -> VerifyResult<Vec<u8>> {
    let envelope: AuditEnvelope = serde_json::from_str(json)?;
    canonical_bytes_of(&envelope)
}

/// Canonical bytes of a parsed envelope (`signature` nulled, sorted maps) —
/// ADR-016: the SAME bytes define the HMAC signature, `prev_hash`, ledger
/// `envelope_hash`, and checkpoint `prior_head`/`new_head` (one form).
pub fn canonical_bytes_of(envelope: &AuditEnvelope) -> VerifyResult<Vec<u8>> {
    let mut canonical = envelope.clone();
    canonical.signature = None;
    Ok(serde_json::to_vec(&canonical)?)
}

/// SHA-256 (hex) of an envelope's canonical bytes — the `prev_hash` value a
/// successor stores (and the ledger `envelope_hash`).
pub fn envelope_hash(json: &str) -> VerifyResult<String> {
    let envelope: AuditEnvelope = serde_json::from_str(json)?;
    envelope_hash_of(&envelope)
}

/// SHA-256 (hex) of a parsed envelope's canonical bytes.
pub fn envelope_hash_of(envelope: &AuditEnvelope) -> VerifyResult<String> {
    Ok(sha256_hex(&canonical_bytes_of(envelope)?))
}

fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hasher
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

fn truncate8(s: &str) -> &str {
    &s[..s.len().min(8)]
}

// ─── ADR-016: local per-producer chain ───────────────────────────────────────

/// Group chained envelopes by producer and sort each chain by sequence.
fn chains_by_producer(envelopes: &[AuditEnvelope]) -> Vec<(String, Vec<&AuditEnvelope>)> {
    let mut by_producer: HashMap<String, Vec<&AuditEnvelope>> = HashMap::new();
    for envelope in envelopes {
        if let (Some(producer), Some(_)) = (envelope.producer_id.as_deref(), envelope.sequence) {
            by_producer
                .entry(producer.to_string())
                .or_default()
                .push(envelope);
        }
    }
    let mut producers: Vec<String> = by_producer.keys().cloned().collect();
    producers.sort();
    producers
        .into_iter()
        .map(|producer| {
            let mut chain = by_producer.remove(&producer).unwrap_or_default();
            chain.sort_by_key(|e| e.sequence.expect("filtered on Some(sequence)"));
            (producer, chain)
        })
        .collect()
}

/// Verify the local per-producer chain (ADR-016 Phase A), strictly — no gap is
/// accepted. For each producer with chained envelopes:
/// - genesis is sequence `0` with no `prev_hash` (a later start = head deletion);
/// - sequences are contiguous and strictly increasing (missing = interior
///   deletion; duplicate/out-of-order = insertion/reorder);
/// - each successor's `prev_hash` equals SHA-256 of the predecessor's canonical
///   bytes.
///
/// Legacy envelopes (`producer_id`/`sequence` = `None`) carry no chain claim and
/// are grandfathered. See [`verify_chain_with_checkpoints`] to accept a range
/// covered by a valid signed compaction checkpoint.
pub fn verify_chain(envelopes: &[AuditEnvelope]) -> VerifyResult<()> {
    verify_chain_with_checkpoints(envelopes, &[], "")
}

/// Verify the local per-producer chain, accepting a gap **iff** it is covered
/// by a valid anchor-signed compaction checkpoint (ADR-016 AC 7): the
/// checkpoint must bracket the gap with `prior_head == hash(before)` and
/// `new_head == prev_hash(after)`, and name exactly the missing sequence range.
/// An uncovered gap fails.
pub fn verify_chain_with_checkpoints(
    envelopes: &[AuditEnvelope],
    checkpoints: &[CompactionCheckpoint],
    anchor_public_key_hex: &str,
) -> VerifyResult<()> {
    // A checkpoint can only excuse a gap after its Ed25519 signature verifies.
    for checkpoint in checkpoints {
        verify_compaction_checkpoint(checkpoint, anchor_public_key_hex)?;
    }

    for (producer, chain) in chains_by_producer(envelopes) {
        if chain.is_empty() {
            continue;
        }
        let base = chain[0].sequence.expect("chained");
        if base != 0 {
            return Err(VerifyError::ChainBroken {
                detail: format!(
                    "producer '{producer}': chain starts at sequence {base}, not genesis 0 — \
                     the earliest envelope(s) were deleted"
                ),
            });
        }
        if chain[0].prev_hash.is_some() {
            return Err(VerifyError::ChainBroken {
                detail: format!(
                    "producer '{producer}': genesis envelope carries a prev_hash — \
                     content was reordered into the genesis slot"
                ),
            });
        }

        for pair in chain.windows(2) {
            let prev = pair[0];
            let next = pair[1];
            let prev_seq = prev.sequence.expect("chained");
            let next_seq = next.sequence.expect("chained");
            if next_seq <= prev_seq {
                return Err(VerifyError::ChainBroken {
                    detail: format!(
                        "producer '{producer}': sequence not strictly increasing \
                         ({prev_seq} -> {next_seq}) — insertion/reorder"
                    ),
                });
            }
            let prev_hash = envelope_hash_of(prev)?;
            if next_seq == prev_seq + 1 {
                match next.prev_hash.as_deref() {
                    Some(actual) if actual == prev_hash => {}
                    Some(actual) => {
                        return Err(VerifyError::ChainBroken {
                            detail: format!(
                                "producer '{producer}': prev_hash mismatch at sequence \
                                 {next_seq} (expected {}…, got {}…)",
                                truncate8(&prev_hash),
                                truncate8(actual),
                            ),
                        });
                    }
                    None => {
                        return Err(VerifyError::ChainBroken {
                            detail: format!(
                                "producer '{producer}': missing prev_hash at sequence {next_seq}"
                            ),
                        });
                    }
                }
                continue;
            }

            // A gap [prev_seq+1, next_seq-1] must be covered by a valid signed
            // checkpoint that brackets it: prior_head == hash(before) and
            // new_head == prev_hash(after) (the link over the erased range).
            let next_link = next
                .prev_hash
                .as_deref()
                .ok_or_else(|| VerifyError::ChainBroken {
                    detail: format!(
                        "producer '{producer}': missing prev_hash after gap at sequence {next_seq}"
                    ),
                })?;
            let covered = checkpoints.iter().any(|c| {
                c.sequence_from == prev_seq + 1
                    && c.sequence_to == next_seq - 1
                    && c.prior_head == prev_hash
                    && c.new_head == next_link
            });
            if !covered {
                return Err(VerifyError::ChainBroken {
                    detail: format!(
                        "producer '{producer}': uncovered gap sequences {}..={} \
                         (missing envelopes with no valid compaction checkpoint)",
                        prev_seq + 1,
                        next_seq - 1,
                    ),
                });
            }
        }
    }
    Ok(())
}

// ─── ADR-016: anchor-signed artifacts (Ed25519) ──────────────────────────────

/// ADR-016 anchor-signed ledger receipt.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LedgerReceipt {
    pub ledger_id: String,
    pub envelope_hash: String,
    pub sequence: u64,
    pub recorded_at: DateTime<Utc>,
    /// `None` only while computing the signing bytes (`sig` nulled).
    pub sig: Option<String>,
}

/// One prior action in an anchor-signed history slice (mirrors engine
/// `HistoryAction`; parameter values never appear).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistoryActionRef {
    pub node: String,
    pub principal: Option<String>,
    pub at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub effect_key: Option<String>,
}

/// ADR-016 anchor-signed history projection the guard consumes in anchored mode.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistorySlice {
    pub scope: String,
    pub since: DateTime<Utc>,
    pub actions: Vec<HistoryActionRef>,
    pub head_hash: String,
    pub sig: Option<String>,
}

/// ADR-016 anchor-signed compaction checkpoint.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompactionCheckpoint {
    pub sequence_from: u64,
    pub sequence_to: u64,
    pub reason: String,
    pub prior_head: String,
    pub new_head: String,
    pub sig: Option<String>,
}

// ─── Effect commitment (ADR-019 / SDK 0.7.0) ────────────────────────────────
//
// Mirrors rigorix-oss `effect_commitment` (state machine, ObservedOutcome) and
// the frozen enterprise wire record (`EffectRecordResponse`). The artifact is
// the PAIR — record + the evidence that settled it — because the wire record
// alone carries no evidence and a `committed` claim with no receipt behind it
// must not verify.

/// Lifecycle state of a recorded effect (mirrors rigorix-oss `EffectState`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EffectState {
    /// Durable intent recorded; the effect has been (or is being) sent.
    Dispatched,
    /// Provider evidence proves the effect committed (terminal for this attempt).
    Committed,
    /// Provider evidence proves the effect did not commit (terminal for this attempt).
    NotCommitted,
    /// The outcome is unknown until a resolver presents provider evidence.
    /// Deliberately NOT terminal.
    Ambiguous,
}

impl EffectState {
    /// Whether no further transition is legal for this attempt.
    pub fn is_terminal(&self) -> bool {
        matches!(self, Self::Committed | Self::NotCommitted)
    }

    /// The canonical snake_case wire label.
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Dispatched => "dispatched",
            Self::Committed => "committed",
            Self::NotCommitted => "not_committed",
            Self::Ambiguous => "ambiguous",
        }
    }
}

impl std::fmt::Display for EffectState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// What a provider read-back proved (mirrors rigorix-oss `OutcomeVerdict`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OutcomeVerdict {
    Committed,
    NotCommitted,
}

impl OutcomeVerdict {
    /// The terminal state this verdict authorises.
    pub fn terminal_state(&self) -> EffectState {
        match self {
            Self::Committed => EffectState::Committed,
            Self::NotCommitted => EffectState::NotCommitted,
        }
    }

    /// The canonical snake_case wire label.
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Committed => "committed",
            Self::NotCommitted => "not_committed",
        }
    }
}

/// The class of a resolver (mirrors enterprise `ResolverKind`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ResolverKind {
    Operator,
    Reconciler,
    BreakGlass,
}

/// Who settled an ambiguous attempt (`ResolverIdentity`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResolverIdentity {
    pub actor: String,
    pub kind: ResolverKind,
}

/// The frozen wire record (mirrors enterprise `EffectRecordResponse`).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EffectRecord {
    pub id: uuid::Uuid,
    pub intent_key: String,
    pub dag_id: String,
    pub node_id: String,
    pub attempt: u32,
    pub state: EffectState,
    pub dispatched_by: String,
    pub deadline: Option<DateTime<Utc>>,
    pub reason: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// Provider evidence that settled an attempt (mirrors OSS `ObservedOutcome`),
/// plus the exact read-back bytes and the optional resolver.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SettlementEvidence {
    pub receipt_id: String,
    pub readback_digest: String,
    pub observed_at: DateTime<Utc>,
    pub source: String,
    pub verdict: OutcomeVerdict,
    /// Exact provider response bytes (UTF-8). Optional: absent means only the
    /// structural claim is available.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub readback: Option<String>,
    /// Present only when an `ambiguous` attempt was settled by a resolver.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resolver: Option<ResolverIdentity>,
}

/// Durability axis: how long the record survives.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Durability {
    /// In-process only: after a restart there is no record, no fence, no sweep.
    L1,
    /// Shared/durable: records and fences survive process death.
    L2,
}

/// Settlement axis: whether provider evidence can prove the effect settled.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SettlementLevel {
    /// The deployment can prove not-settled, never settled.
    None,
    /// A configured provider read-back can prove settlement.
    L3,
}

/// What the producing deployment can do, on two independent axes.
///
/// `l1` durability + `l3` settlement is legitimate (an in-process ledger with a
/// receipt reader). Never collapse the axes into one label (#1182).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClaimLevels {
    pub durability: Durability,
    pub settlement: SettlementLevel,
}

/// The effect-commitment artifact: record + settlement evidence + levels.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EffectRecordArtifact {
    pub record: EffectRecord,
    /// Legality is state-dependent: terminal states require it, non-terminal
    /// states forbid it (`verify_effect_record`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub settlement: Option<SettlementEvidence>,
    pub levels: ClaimLevels,
}

/// Canonical signing bytes for a ledger receipt (`sig` nulled).
pub fn ledger_receipt_signing_bytes(receipt: &LedgerReceipt) -> VerifyResult<Vec<u8>> {
    let mut unsigned = receipt.clone();
    unsigned.sig = None;
    Ok(serde_json::to_vec(&unsigned)?)
}

/// Canonical signing bytes for a history slice (`sig` nulled).
pub fn history_slice_signing_bytes(slice: &HistorySlice) -> VerifyResult<Vec<u8>> {
    let mut unsigned = slice.clone();
    unsigned.sig = None;
    Ok(serde_json::to_vec(&unsigned)?)
}

/// Canonical signing bytes for a compaction checkpoint (`sig` nulled).
pub fn compaction_checkpoint_signing_bytes(
    checkpoint: &CompactionCheckpoint,
) -> VerifyResult<Vec<u8>> {
    let mut unsigned = checkpoint.clone();
    unsigned.sig = None;
    Ok(serde_json::to_vec(&unsigned)?)
}

fn public_key_from_hex(public_key_hex: &str) -> VerifyResult<VerifyingKey> {
    let bytes = hex::decode(public_key_hex)
        .map_err(|e| VerifyError::AnchorSignature(format!("public key hex: {e}")))?;
    let arr: [u8; 32] = bytes
        .as_slice()
        .try_into()
        .map_err(|_| VerifyError::AnchorSignature("public key must be 32 bytes".to_string()))?;
    VerifyingKey::from_bytes(&arr).map_err(|e| VerifyError::AnchorSignature(e.to_string()))
}

/// Verify an Ed25519 signature (`sig_hex`, 64 bytes) over `canonical` with the
/// anchor's public key (`public_key_hex`, 32 bytes).
pub fn verify_ed25519(canonical: &[u8], sig_hex: &str, public_key_hex: &str) -> VerifyResult<()> {
    let key = public_key_from_hex(public_key_hex)?;
    let sig_bytes = hex::decode(sig_hex)
        .map_err(|e| VerifyError::AnchorSignature(format!("signature hex: {e}")))?;
    let arr: [u8; 64] = sig_bytes
        .as_slice()
        .try_into()
        .map_err(|_| VerifyError::AnchorSignature("signature must be 64 bytes".to_string()))?;
    let signature = Signature::from_bytes(&arr);
    key.verify(canonical, &signature)
        .map_err(|e| VerifyError::AnchorSignature(e.to_string()))
}

/// Verify a ledger receipt's Ed25519 signature.
pub fn verify_ledger_receipt(receipt: &LedgerReceipt, public_key_hex: &str) -> VerifyResult<()> {
    let sig = receipt.sig.clone().unwrap_or_default();
    verify_ed25519(
        &ledger_receipt_signing_bytes(receipt)?,
        &sig,
        public_key_hex,
    )
}

/// Verify a history slice's Ed25519 signature.
pub fn verify_history_slice(slice: &HistorySlice, public_key_hex: &str) -> VerifyResult<()> {
    let sig = slice.sig.clone().unwrap_or_default();
    verify_ed25519(&history_slice_signing_bytes(slice)?, &sig, public_key_hex)
}

/// Verify a compaction checkpoint's Ed25519 signature.
pub fn verify_compaction_checkpoint(
    checkpoint: &CompactionCheckpoint,
    public_key_hex: &str,
) -> VerifyResult<()> {
    let sig = checkpoint.sig.clone().unwrap_or_default();
    verify_ed25519(
        &compaction_checkpoint_signing_bytes(checkpoint)?,
        &sig,
        public_key_hex,
    )
}

/// Structural verification of an effect-commitment artifact.
///
/// Independently re-checks what the engine's `EffectRecord::hydrate` enforces:
///
/// - a terminal state carries settlement evidence (`EvidenceMissing`);
/// - a non-terminal state carries none — no outcome, no resolver (`Contended`);
/// - `dispatched` carries a deadline;
/// - the verdict authorises the record's terminal state;
/// - evidence implies the deployment's settlement level is `l3`.
///
/// It does NOT bind the record to a signed envelope: the record is unsigned and
/// its intent is not derivable from the envelope (see the schema ceiling).
pub fn verify_effect_record(artifact: &EffectRecordArtifact) -> VerifyResult<()> {
    let record = &artifact.record;

    if record.state == EffectState::Dispatched && record.deadline.is_none() {
        return Err(VerifyError::EffectInvariant {
            detail: "dispatched record must carry a deadline".to_string(),
        });
    }

    match (record.state.is_terminal(), artifact.settlement.as_ref()) {
        (true, None) => {
            return Err(VerifyError::EffectInvariant {
                detail: format!(
                    "terminal state `{}` must carry settlement evidence (EvidenceMissing)",
                    record.state
                ),
            });
        }
        (false, Some(_)) => {
            return Err(VerifyError::EffectInvariant {
                detail: format!(
                    "non-terminal state `{}` must not carry settlement evidence (Contended)",
                    record.state
                ),
            });
        }
        _ => {}
    }

    if let Some(settlement) = artifact.settlement.as_ref() {
        let authorised = settlement.verdict.terminal_state();
        if authorised != record.state {
            return Err(VerifyError::EffectInvariant {
                detail: format!(
                    "settlement verdict `{}` authorises `{}`, but the record is `{}`",
                    settlement.verdict.as_str(),
                    authorised,
                    record.state
                ),
            });
        }
        if artifact.levels.settlement != SettlementLevel::L3 {
            return Err(VerifyError::EffectInvariant {
                detail: "settlement evidence is present but levels.settlement is `none`"
                    .to_string(),
            });
        }
    }

    Ok(())
}

/// Readback verification: re-derive `readback_digest` from the exact provider
/// bytes carried in `settlement.readback` (`hex(SHA-256(bytes))`).
///
/// This is the level that makes "settled" a claim rather than a field: the
/// provider is the authority for the effect, the record is not. A missing body
/// is refused rather than silently downgraded to the structural claim.
pub fn verify_settlement_evidence(artifact: &EffectRecordArtifact) -> VerifyResult<()> {
    verify_effect_record(artifact)?;
    let settlement = artifact
        .settlement
        .as_ref()
        .ok_or_else(|| VerifyError::EffectInvariant {
            detail: "no settlement evidence to verify".to_string(),
        })?;
    let readback = settlement
        .readback
        .as_ref()
        .ok_or(VerifyError::ReadbackMissing)?;
    let got = hex::encode(Sha256::digest(readback.as_bytes()));
    if got != settlement.readback_digest {
        return Err(VerifyError::ReadbackDigestMismatch {
            expected: settlement.readback_digest.clone(),
            got,
        });
    }
    Ok(())
}

/// Compute the HMAC-SHA256 hex signature over the canonical form.
pub fn sign(json: &str, key: &str) -> VerifyResult<String> {
    let mut mac = HmacSha256::new_from_slice(key.as_bytes())
        .map_err(|e| VerifyError::HmacKey(e.to_string()))?;
    mac.update(&canonical_bytes(json)?);
    Ok(hex::encode(mac.finalize().into_bytes()))
}

/// Verify an envelope's signature over its canonical form.
///
/// GAP-M-12: an envelope with `signature: null` is only acceptable when
/// `evidence_degraded: true` (explicitly produced unsigned). A null signature
/// without the marker is treated as tampering evidence.
pub fn verify_signature(json: &str, key: &str) -> VerifyResult<()> {
    let envelope: AuditEnvelope = serde_json::from_str(json)?;
    let Some(expected) = envelope.signature.as_ref() else {
        if envelope.evidence_degraded {
            return Ok(()); // intentionally unsigned, explicitly marked
        }
        return Err(VerifyError::UnsignedNotDegraded);
    };
    let got = sign(json, key)?;
    if constant_time_eq(expected, &got) {
        Ok(())
    } else {
        Err(VerifyError::SignatureMismatch {
            expected: expected.clone(),
            got,
        })
    }
}

/// Validate an envelope against the SDK envelope schema (`envelope.json`).
///
/// The schema resolves from `RIGORIX_SDK_SCHEMAS` (explicit override) or the
/// embedded `rigorix-schemas` corpus — never from the repo layout.
pub fn validate_schema(json: &str) -> VerifyResult<()> {
    validate_schema_file("envelope.json", json)
}

/// Validate any JSON instance against a named SDK schema file.
fn validate_schema_file(file: &str, json: &str) -> VerifyResult<()> {
    let schema_text = schema_text(file)?;
    let schema = serde_json::from_str(&schema_text)?;
    let instance: serde_json::Value = serde_json::from_str(json)?;
    let compiled = build_validator(file, &schema)?;
    let errors: Vec<String> = compiled
        .iter_errors(&instance)
        .map(|e| e.to_string())
        .collect();
    if !errors.is_empty() {
        return Err(VerifyError::Schema(errors.join("; ")));
    }
    Ok(())
}

/// Resolve a contract's JSON text (SDK-VERIFIER-PUBLISH resolution order).
///
/// 1. `RIGORIX_SDK_SCHEMAS` — an explicit external corpus (CI/local override).
/// 2. The embedded `rigorix-schemas` corpus — the published, self-contained path.
///
/// There is deliberately **no** `CARGO_MANIFEST_DIR/../../schemas` fallback: a
/// published verifier must not depend on the repo layout.
fn schema_text(file: &str) -> VerifyResult<String> {
    if let Ok(dir) = std::env::var("RIGORIX_SDK_SCHEMAS") {
        let path = Path::new(&dir).join(file);
        if !path.exists() {
            return Err(VerifyError::SchemaRead(format!(
                "RIGORIX_SDK_SCHEMAS set but {} missing",
                path.display()
            )));
        }
        return std::fs::read_to_string(&path)
            .map_err(|e| VerifyError::SchemaRead(format!("{}: {e}", path.display())));
    }
    rigorix_schemas::schema(file)
        .map(str::to_string)
        .ok_or_else(|| {
            VerifyError::SchemaRead(format!(
                "schema `{file}` not found — set RIGORIX_SDK_SCHEMAS or use the embedded \
             rigorix-schemas corpus"
            ))
        })
}

/// Verify that every method in `candidate` is declared in the frozen catalog
/// (`schemas/api/catalog.json`).
///
/// ADR-0001 D3: the `rigorix.*` namespace is **closed** — a server implements a
/// SUBSET of the frozen catalog and MUST NOT register an undeclared method.
/// Server CI / conformance passes the method set it serves; an unknown
/// `rigorix.*` name is a contract violation (SDK-C5 / #15).
pub fn verify_catalog_subset(candidate: &[&str]) -> VerifyResult<()> {
    let text = schema_text("api/catalog.json")?;
    let catalog: serde_json::Value = serde_json::from_str(&text)?;
    let declared: std::collections::HashSet<&str> = catalog["methods"]
        .as_array()
        .ok_or_else(|| VerifyError::Schema("catalog.json: methods is not an array".to_string()))?
        .iter()
        .filter_map(|method| method["name"].as_str())
        .collect();
    for method in candidate {
        if !declared.contains(method) {
            return Err(VerifyError::UndeclaredMethod((*method).to_string()));
        }
    }
    Ok(())
}

/// The `$id` of the canonical envelope schema — a cross-file `$ref` target on
/// the contract surface (`api/events.json` → `envelope.json`).
const ENVELOPE_SCHEMA_ID: &str = "https://rigorix.eu/schemas/envelope-v2.json";

/// The `$id` of the canonical claims schema — the home of the shared identity
/// shapes, a cross-file `$ref` target from the catalog
/// (`api/catalog.json` → `claims.json#/$defs/identityRef|identityClaim`).
const CLAIMS_SCHEMA_ID: &str = "https://rigorix.eu/schemas/claims.json";

/// The `$id` of the ADR-016 history-slice schema — the result shape of
/// `rigorix.audit.history`, referenced cross-file from the catalog.
const HISTORY_SLICE_SCHEMA_ID: &str = "https://rigorix.eu/schemas/api/history-slice-v1.json";

/// The `$id` of the consequence-gating §4.3 authority-fact bundle schema — the
/// result shape of `rigorix.audit.authorityFacts`, referenced cross-file from
/// the catalog. It in turn `$ref`s the one canonical envelope dialect.
const AUTHORITY_FACT_BUNDLE_SCHEMA_ID: &str =
    "https://rigorix.eu/schemas/api/authority-fact-bundle-v1.json";

/// Build a JSON Schema validator, registering sibling contract schemas so
/// cross-file `$ref`s resolve offline (`events.json` → `envelope.json`;
/// `api/catalog.json` → `claims.json`).
///
/// The schema being compiled is never registered as its own sibling resource.
fn build_validator(file: &str, schema: &serde_json::Value) -> VerifyResult<jsonschema::Validator> {
    let mut options = jsonschema::options();
    for (sibling, id) in [
        ("envelope.json", ENVELOPE_SCHEMA_ID),
        ("claims.json", CLAIMS_SCHEMA_ID),
        ("api/history-slice.json", HISTORY_SLICE_SCHEMA_ID),
        (
            "api/authority-fact-bundle.json",
            AUTHORITY_FACT_BUNDLE_SCHEMA_ID,
        ),
    ] {
        if file == sibling {
            continue;
        }
        let text = schema_text(sibling)?;
        let value: serde_json::Value = serde_json::from_str(&text)?;
        let resource = jsonschema::Resource::from_contents(value)
            .map_err(|e| VerifyError::Schema(e.to_string()))?;
        options.with_resource(id, resource);
    }
    options
        .build(schema)
        .map_err(|e| VerifyError::Schema(e.to_string()))
}

/// Constant-time comparison for hex signatures.
fn constant_time_eq(a: &str, b: &str) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.bytes()
        .zip(b.bytes())
        .fold(0u8, |acc, (x, y)| acc | (x ^ y))
        == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    // ─── Contract resolution (env override -> embedded rigorix-schemas) ───
    //
    // Tests must exercise the PUBLISHED resolution path: with no override they
    // read the embedded corpus, exactly like a consumer of the packaged crate.

    /// Read a fixture by path relative to `schemas/fixtures/`.
    fn fixture_text(rel: &str) -> String {
        if let Ok(dir) = std::env::var("RIGORIX_SDK_SCHEMAS") {
            let path = Path::new(&dir).join("fixtures").join(rel);
            return std::fs::read_to_string(&path)
                .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        }
        rigorix_schemas::fixture(rel)
            .map(str::to_string)
            .unwrap_or_else(|| panic!("fixture `{rel}` is not embedded in rigorix-schemas"))
    }

    /// Every `.json` fixture path relative to `fixtures/<prefix>/`, sorted.
    fn fixture_json_names(prefix: &str) -> Vec<String> {
        if let Ok(dir) = std::env::var("RIGORIX_SDK_SCHEMAS") {
            let root = Path::new(&dir).join("fixtures").join(prefix);
            let mut out = Vec::new();
            collect_json(&root, &root, &mut out);
            out.sort();
            return out;
        }
        let needle = format!("fixtures/{prefix}/");
        let mut out: Vec<String> = rigorix_schemas::schema_names()
            .iter()
            .filter_map(|name| name.strip_prefix(&needle))
            .filter(|rel| rel.ends_with(".json"))
            .map(str::to_string)
            .collect();
        out.sort();
        out
    }

    fn collect_json(root: &Path, dir: &Path, out: &mut Vec<String>) {
        let entries =
            std::fs::read_dir(dir).unwrap_or_else(|e| panic!("read {}: {e}", dir.display()));
        for entry in entries {
            let path = entry.expect("dir entry").path();
            if path.is_dir() {
                collect_json(root, &path, out);
            } else if path.extension().and_then(|e| e.to_str()) == Some("json") {
                out.push(
                    path.strip_prefix(root)
                        .expect("under fixture root")
                        .to_string_lossy()
                        .replace('\\', "/"),
                );
            }
        }
    }

    const KEY: &str = "test-hmac-key";

    fn minimal_envelope() -> String {
        serde_json::json!({
            "execution_id": "c24a5a7e-1f4d-4f0e-9b3a-8e0d3a1b2c3d",
            "timestamp": "2026-09-07T10:00:00Z",
            "template_id": "conference-registration",
            "planning_hash": "abc123",
            "total_tokens": 1000,
            "duration_ms": 5000,
            "events": [
                {
                    "event_type": "tool_executed",
                    "summary": "removed alice",
                    "occurred_at": "2026-09-07T09:59:59Z",
                    "status": "Success"
                }
            ],
            "signature": null,
            "evidence_degraded": false
        })
        .to_string()
    }

    fn signed_envelope() -> String {
        let json = minimal_envelope();
        let sig = sign(&json, KEY).unwrap();
        let mut v: serde_json::Value = serde_json::from_str(&json).unwrap();
        v["signature"] = serde_json::Value::String(sig);
        v.to_string()
    }

    #[test]
    fn sign_and_verify_roundtrip() {
        let envelope = signed_envelope();
        assert!(verify_signature(&envelope, KEY).is_ok());
    }

    #[test]
    fn tampering_detected() {
        let mut v: serde_json::Value = serde_json::from_str(&signed_envelope()).unwrap();
        v["total_tokens"] = serde_json::json!(9999); // tamper
        let err = verify_signature(&v.to_string(), KEY).unwrap_err();
        assert!(matches!(err, VerifyError::SignatureMismatch { .. }));
    }

    #[test]
    fn unsigned_must_be_degraded() {
        // signature null, evidence_degraded false → GAP-M-12 violation
        let err = verify_signature(&minimal_envelope(), KEY).unwrap_err();
        assert!(matches!(err, VerifyError::UnsignedNotDegraded));
    }

    #[test]
    fn unsigned_marked_degraded_is_ok() {
        let mut v: serde_json::Value = serde_json::from_str(&minimal_envelope()).unwrap();
        v["evidence_degraded"] = serde_json::json!(true);
        assert!(verify_signature(&v.to_string(), KEY).is_ok());
    }

    #[test]
    fn wrong_key_fails() {
        let envelope = signed_envelope();
        let err = verify_signature(&envelope, "wrong-key").unwrap_err();
        assert!(matches!(err, VerifyError::SignatureMismatch { .. }));
    }

    #[test]
    fn canonical_stability() {
        // Parsing + re-serializing twice must produce identical canonical bytes.
        let a = canonical_bytes(&minimal_envelope()).unwrap();
        let b = canonical_bytes(&minimal_envelope()).unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn schema_conformance_of_minimal() {
        // minimal_envelope is unsigned with evidence_degraded=false — schema
        // allows it (schema describes shape, not policy); verifier policy
        // (GAP-M-12) is enforced in verify_signature.
        assert!(validate_schema(&minimal_envelope()).is_ok());
    }

    #[test]
    fn schema_rejects_wrong_status_case() {
        // v1 schema requires serde-exact capitalized EventStatus; lowercase
        // `success` must fail schema validation.
        let mut v: serde_json::Value = serde_json::from_str(&minimal_envelope()).unwrap();
        v["events"][0]["status"] = serde_json::json!("success");
        let err = validate_schema(&v.to_string()).unwrap_err();
        assert!(matches!(err, VerifyError::Schema(_)));
    }

    // ─── ADR-015 operator step-requirements (R9) ──────────────────────────
    //
    // Grounded in rigorix-oss `sequence_policy/domain/requirement.rs` +
    // `audit/domain/envelope.rs` (code is truth).
    #[test]
    fn policy_schema_round_trips_step_requirement() {
        let policy = serde_json::json!({
            "fail_closed": true,
            "rules": [],
            "requirements": [{
                "id": "payout-guard",
                "name": "Payout commands must be attested and carry effect data",
                "description": "d",
                "match": {
                    "tool": "run_command",
                    "params": [{
                        "pointer": "/command",
                        "kind": "glob",
                        "value": "*execute_payout.sh*"
                    }]
                },
                "require_identity": true,
                "require_params": ["/beneficiary", "/effect_key"],
                "action": "deny"
            }]
        });
        assert!(validate_schema_file("policy.json", &policy.to_string()).is_ok());

        // `action` is serde-defaulted — a requirement may omit it.
        let mut defaulted = policy.clone();
        defaulted["requirements"][0]
            .as_object_mut()
            .unwrap()
            .remove("action");
        assert!(validate_schema_file("policy.json", &defaulted.to_string()).is_ok());

        // `name` has NO serde default on StepRequirement — it is required.
        let mut missing_name = policy.clone();
        missing_name["requirements"][0]
            .as_object_mut()
            .unwrap()
            .remove("name");
        assert!(validate_schema_file("policy.json", &missing_name.to_string()).is_err());

        // require_params entries are JSON pointers — must start with '/'.
        let mut bad_pointer = policy.clone();
        bad_pointer["requirements"][0]["require_params"] = serde_json::json!(["beneficiary"]);
        assert!(validate_schema_file("policy.json", &bad_pointer.to_string()).is_err());
    }

    #[test]
    fn envelope_schema_accepts_requirement_findings() {
        let mut v: serde_json::Value = serde_json::from_str(&minimal_envelope()).unwrap();
        v["requirement_findings"] = serde_json::json!([{
            "requirement_id": "payout-guard",
            "step": "pay",
            "action": "deny",
            "unmet": ["identity", "/beneficiary"],
            "summary": "operator requirement 'payout-guard' denied step 'pay'"
        }]);
        assert!(validate_schema(&v.to_string()).is_ok());

        // `unmet` is required on RequirementFindingRef.
        let mut bad = v.clone();
        bad["requirement_findings"][0]
            .as_object_mut()
            .unwrap()
            .remove("unmet");
        assert!(validate_schema(&bad.to_string()).is_err());

        // Action is the lowercase serde set — `DENY` is not a valid value.
        let mut wrong_action = v.clone();
        wrong_action["requirement_findings"][0]["action"] = serde_json::json!("DENY");
        assert!(validate_schema(&wrong_action.to_string()).is_err());
    }

    // ─── Real engine fixture corpus (F-20260907-01) ────────────────────────
    //
    // Envelopes in schemas/fixtures/envelope/*.json are produced by REAL
    // rigorix-oss engine runs (fixed test key fixture-hmac-key-2026, see the
    // README there). Verifying them byte-exact proves canonicalization parity
    // between the engine and this independent verifier — the Strategy A
    // claim that the HMAC trail is checkable anywhere.
    #[test]
    fn engine_signed_fixtures_verify_byte_exact() {
        let key = "fixture-hmac-key-2026";
        let names = fixture_json_names("envelope");
        let mut found = 0;
        for name in &names {
            let json = fixture_text(&format!("envelope/{name}"));
            // Independent verifier accepts the engine's signature byte-exact.
            verify_signature(&json, key).unwrap_or_else(|e| panic!("{name}: {e}"));
            // And the envelope conforms to the SDK schema.
            validate_schema(&json).unwrap_or_else(|e| panic!("{name}: {e}"));
            found += 1;
        }
        assert!(
            found >= 3,
            "expected ≥3 committed engine fixtures, found {found}"
        );
    }

    /// #1243: an approval ref states whether its intent hash was derived by
    /// the engine or asserted by a caller. The field is required and sits in
    /// the signed bytes immediately after `intent_hash`.
    #[test]
    fn approval_ref_provenance_is_required_and_signed() {
        let json = fixture_text("envelope/envelope-rich-signed.json");
        let envelope: AuditEnvelope = serde_json::from_str(&json).expect("fixture parses");
        let approval = envelope
            .approval_events
            .first()
            .expect("rich fixture carries an approval");
        assert_eq!(
            approval.intent_hash_provenance,
            IntentHashProvenance::Derived,
            "the OSS engine emits derived intent hashes"
        );

        let mut value: serde_json::Value = serde_json::from_str(&json).expect("json");
        let refs = value["approval_events"]
            .as_array_mut()
            .expect("approval_events");
        refs[0]["intent_hash_provenance"] = serde_json::json!("asserted");
        let asserted = serde_json::to_string(&value).expect("serialize");
        validate_schema(&asserted).expect("asserted is a valid, weaker kind");
        let asserted_envelope: AuditEnvelope =
            serde_json::from_value(value.clone()).expect("asserted parses");
        assert_eq!(
            asserted_envelope.approval_events[0].intent_hash_provenance,
            IntentHashProvenance::Asserted
        );

        value["approval_events"][0]
            .as_object_mut()
            .expect("approval ref")
            .remove("intent_hash_provenance");
        let missing = serde_json::to_string(&value).expect("serialize");
        assert!(
            validate_schema(&missing).is_err(),
            "schema must reject an approval ref that does not state provenance"
        );
        assert!(
            serde_json::from_value::<AuditEnvelope>(value).is_err(),
            "deserialization must reject a missing provenance, not default it"
        );
    }

    /// SDK #31 / ADR-016 Phase C regression: the anchored engine fixture's HMAC
    /// reproduces ONLY when `anchor_head` sits after `history_policy` and before
    /// `approval_events`. Before the field was declared the verifier dropped it,
    /// so this failed with `SignatureMismatch` on authentic anchored evidence.
    #[test]
    fn anchored_envelope_binds_anchor_head_at_engine_position() {
        const HEAD: &str = "3f2a9c1e7b4d5f6081a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708";
        let json = fixture_text("envelope/envelope-anchored-signed.json");
        let envelope: AuditEnvelope = serde_json::from_str(&json).expect("anchored fixture parses");
        assert_eq!(envelope.history_integrity, Some(HistoryIntegrity::Anchored));
        assert_eq!(envelope.anchor_head.as_deref(), Some(HEAD));
        assert!(
            !envelope.approval_events.is_empty(),
            "fixture must carry approval_events (position proof)"
        );

        // Byte-exact parity — the regression: dropping the field breaks this.
        verify_signature(&json, "fixture-hmac-key-2026")
            .expect("anchored fixture verifies byte-exact");
        validate_schema(&json).expect("anchored fixture conforms to envelope.json");

        // The field is signed, in the engine's declared position.
        let bytes = canonical_bytes_of(&envelope).expect("canonical bytes");
        let canonical = String::from_utf8(bytes).expect("utf8");
        let head_at = canonical
            .find("\"anchor_head\"")
            .expect("anchor_head is part of the signed bytes");
        let approvals_at = canonical
            .find("\"approval_events\"")
            .expect("approval_events present");
        assert!(
            head_at < approvals_at,
            "anchor_head must precede approval_events"
        );

        // Tampering with the head is detected (it is not ignored).
        let tampered = json.replacen(HEAD, &"0".repeat(64), 1);
        assert!(matches!(
            verify_signature(&tampered, "fixture-hmac-key-2026"),
            Err(VerifyError::SignatureMismatch { .. })
        ));

        // A legacy fixture has no anchor_head — skip-if-none keeps its bytes
        // unchanged (Phase A regression guard).
        let local = fixture_text("envelope/envelope-minimal-signed.json");
        assert!(!local.contains("\"anchor_head\""));
        verify_signature(&local, "fixture-hmac-key-2026").expect("local fixture unchanged");
    }

    /// SDK #39 / ADR-017: write the contract-first `precondition_findings[]`
    /// fixture. The engine does not implement ADR-017 yet, so the reference
    /// verifier signs a minimal envelope (the cross-language check is that
    /// Python/TS/Java/Go independently reproduce the bytes). Regenerate from the
    /// engine once ADR-017 Phase B lands.
    #[test]
    #[ignore = "writes the ADR-017 precondition fixture (contract-first)"]
    fn generate_precondition_fixture() {
        let base = fixture_text("envelope/envelope-minimal-signed.json");
        let mut value: serde_json::Value =
            serde_json::from_str(&base).expect("minimal fixture parses");
        let obj = value.as_object_mut().expect("object");
        let _ = obj.remove("signature");
        obj.insert(
            "precondition_findings".to_string(),
            serde_json::json!([
                {
                    "precondition_id": "beneficiary-eligible",
                    "step": "risky_step",
                    "outcome": "failed",
                    "exit_code": 3,
                    "inputs_hash": "5f2a9c1e7b4d5f6081a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708",
                    "checked_at": "2026-10-01T12:00:00Z",
                    "summary": "authority check denied dispatch (exit 3)",
                    "check_digest": "sha256:1111111111111111111111111111111111111111111111111111111111111111",
                    "authority_digest": "sha256:2222222222222222222222222222222222222222222222222222222222222222",
                    "check_writable": false,
                    "attribution": "recorded"
                },
                {
                    "precondition_id": "account-open",
                    "step": "run_command",
                    "outcome": "passed",
                    "exit_code": 0,
                    "inputs_hash": "1c2b3a495867798a0b1c2d3e4f5061728394a5b6c7d8e9f0a1b2c3d4e5f60718",
                    "checked_at": "2026-10-01T12:00:01Z",
                    "summary": "authority stands",
                    "check_digest": "sha256:1111111111111111111111111111111111111111111111111111111111111111",
                    "check_writable": true,
                    "attribution": "recorded"
                },
                {
                    "precondition_id": "network-eligible",
                    "step": "run_command",
                    "outcome": "error",
                    "exit_code": null,
                    "inputs_hash": "9e8d7c6b5a4938271605f4e3d2c1b0a99887766554433221100ffeeddccbbaa",
                    "checked_at": "2026-10-01T12:00:02Z",
                    "summary": "check refused before it ran",
                    "attribution": "refused_before_check"
                },
                {
                    "precondition_id": "payout-authority",
                    "step": "run_command",
                    "outcome": "failed",
                    "exit_code": 5,
                    "inputs_hash": "0a1b2c3d4e5f60718293a4b5c6d7e8f90123456789abcdef0123456789abcdef",
                    "checked_at": "2026-10-01T12:00:03Z",
                    "summary": "authority check denied dispatch (exit 5)",
                    "check_digest": "sha256:1111111111111111111111111111111111111111111111111111111111111111",
                    "attribution": "artifact_unreadable"
                }
            ]),
        );
        let signature = sign(&value.to_string(), FIXTURE_KEY).expect("sign fixture");
        let mut envelope: AuditEnvelope =
            serde_json::from_value(value).expect("fixture parses into AuditEnvelope");
        envelope.signature = Some(signature);
        let json = serde_json::to_string_pretty(&envelope).expect("serialize fixture");
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../schemas/fixtures/envelope/envelope-precondition-signed.json");
        std::fs::write(&path, format!("{json}\n")).expect("write fixture");
        eprintln!("wrote {}", path.display());
    }

    /// SDK #47 / ADR-016: write a fixture envelope carrying the third
    /// `historyIntegrity` value `anchored_pending` (anchored mode configured,
    /// no verified head). Derived from the engine-signed `anchored` fixture by
    /// dropping the unverified `anchor_head` and re-signing with the fixed test
    /// key; the engine emits this value in the same shape
    /// (`envelope_factory_impl.rs`: `AnchoredPending => anchor_head: None`).
    /// Contract-first until the engine's conformance writer emits it directly.
    #[test]
    #[ignore = "writes the anchored_pending fixture (contract-first)"]
    fn generate_anchored_pending_fixture() {
        let base = fixture_text("envelope/envelope-anchored-signed.json");
        let mut value: serde_json::Value =
            serde_json::from_str(&base).expect("anchored fixture parses");
        let obj = value.as_object_mut().expect("object");
        let _ = obj.remove("signature");
        // `anchored_pending` pairs with `anchor_head: None` in the engine.
        let _ = obj.remove("anchor_head");
        obj.insert(
            "history_integrity".to_string(),
            serde_json::json!("anchored_pending"),
        );
        let signature = sign(&value.to_string(), FIXTURE_KEY).expect("sign fixture");
        let mut envelope: AuditEnvelope =
            serde_json::from_value(value).expect("fixture parses into AuditEnvelope");
        assert_eq!(
            envelope.history_integrity,
            Some(HistoryIntegrity::AnchoredPending)
        );
        assert!(envelope.anchor_head.is_none());
        envelope.signature = Some(signature);
        let json = serde_json::to_string_pretty(&envelope).expect("serialize fixture");
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../schemas/fixtures/envelope/envelope-anchored-pending-signed.json");
        std::fs::write(&path, format!("{json}\n")).expect("write fixture");
        eprintln!("wrote {}", path.display());
    }

    /// SDK #47: the `anchored_pending` fixture is schema-valid and HMAC-valid,
    /// and the label is not a weaker `anchored` (nothing was verified).
    #[test]
    fn anchored_pending_fixture_verifies() {
        let json = fixture_text("envelope/envelope-anchored-pending-signed.json");
        let envelope: AuditEnvelope = serde_json::from_str(&json).expect("fixture parses");
        assert_eq!(
            envelope.history_integrity,
            Some(HistoryIntegrity::AnchoredPending)
        );
        assert!(envelope.anchor_head.is_none(), "nothing was verified");
        assert_ne!(
            envelope.history_integrity,
            Some(HistoryIntegrity::Anchored),
            "anchored_pending must not be treated as authenticated"
        );
        verify_signature(&json, FIXTURE_KEY).expect("fixture verifies byte-exact");
        validate_schema(&json).expect("fixture conforms to envelope.json");

        // The label is part of the signed canonical form.
        let tampered = json.replacen("anchored_pending", "anchored", 1);
        assert!(matches!(
            verify_signature(&tampered, FIXTURE_KEY),
            Err(VerifyError::SignatureMismatch { .. })
        ));
    }

    /// SDK #39 / ADR-017: the contract-first `precondition_findings[]` fixture
    /// verifies byte-exact and is tamper-detected; legacy fixtures are unchanged.
    #[test]
    fn precondition_findings_fixture_verifies() {
        let json = fixture_text("envelope/envelope-precondition-signed.json");
        let envelope: AuditEnvelope = serde_json::from_str(&json).expect("fixture parses");
        assert_eq!(envelope.precondition_findings.len(), 4);
        assert_eq!(envelope.precondition_findings[0].outcome, "failed");
        assert_eq!(envelope.precondition_findings[0].exit_code, Some(3));
        assert_eq!(envelope.precondition_findings[1].outcome, "passed");
        assert_eq!(envelope.precondition_findings[1].exit_code, Some(0));
        assert_eq!(envelope.precondition_findings[2].outcome, "error");
        assert_eq!(envelope.precondition_findings[2].exit_code, None);
        assert_eq!(envelope.precondition_findings[3].outcome, "failed");
        assert_eq!(envelope.precondition_findings[3].exit_code, Some(5));
        // ADR-017 attribution (#987): digests + boundary fact are bound.
        assert_eq!(
            envelope.precondition_findings[0].check_digest.as_deref(),
            Some("sha256:1111111111111111111111111111111111111111111111111111111111111111")
        );
        assert_eq!(
            envelope.precondition_findings[0]
                .authority_digest
                .as_deref(),
            Some("sha256:2222222222222222222222222222222222222222222222222222222222222222")
        );
        assert_eq!(
            envelope.precondition_findings[0].check_writable,
            Some(false)
        );
        // ISSUE-ATTRIBUTION-ABSENCE-REASON: the four states are distinct.
        assert_eq!(
            envelope.precondition_findings[0].attribution.as_deref(),
            Some("recorded")
        );
        assert_eq!(
            envelope.precondition_findings[1].attribution.as_deref(),
            Some("recorded")
        );
        assert_eq!(
            envelope.precondition_findings[2].attribution.as_deref(),
            Some("refused_before_check")
        );
        assert_eq!(
            envelope.precondition_findings[3].attribution.as_deref(),
            Some("artifact_unreadable")
        );
        // A refusal omits the digests; the reason is the machine-readable cause.
        assert_eq!(envelope.precondition_findings[2].check_digest, None);
        assert_eq!(envelope.precondition_findings[2].authority_digest, None);
        // `artifact_unreadable` keeps the digest it could compute and omits the other.
        assert_eq!(
            envelope.precondition_findings[3].check_digest.as_deref(),
            Some("sha256:1111111111111111111111111111111111111111111111111111111111111111")
        );
        assert_eq!(envelope.precondition_findings[3].authority_digest, None);

        verify_signature(&json, "fixture-hmac-key-2026").expect("byte-exact");
        validate_schema(&json).expect("schema conformance");

        let tampered = json.replacen("\"exit_code\": 3", "\"exit_code\": 0", 1);
        assert!(matches!(
            verify_signature(&tampered, "fixture-hmac-key-2026"),
            Err(VerifyError::SignatureMismatch { .. })
        ));

        // A forged authority changes `authority_digest` -> signature mismatch.
        let forged = json.replacen(
            "sha256:2222222222222222222222222222222222222222222222222222222222222222",
            "sha256:3333333333333333333333333333333333333333333333333333333333333333",
            1,
        );
        assert!(matches!(
            verify_signature(&forged, "fixture-hmac-key-2026"),
            Err(VerifyError::SignatureMismatch { .. })
        ));

        let legacy = fixture_text("envelope/envelope-minimal-signed.json");
        assert!(!legacy.contains("precondition_findings"));
        verify_signature(&legacy, "fixture-hmac-key-2026").expect("legacy unchanged");
    }

    // ─── Schema lint (SDK contract surface) ───────────────────────────────
    //
    // Every top-level contract schema must be a well-formed JSON Schema
    // (draft 2020-12) that compiles cleanly. This is the SDK's own guard that
    // the published contract surface never ships a broken schema.
    #[test]
    fn all_schemas_compile() {
        for name in [
            "envelope.json",
            "claims.json",
            "policy.json",
            "api/catalog.schema.json",
            "api/errors.json",
            "api/events.json",
            "api/ledger-receipt.json",
            "api/history-slice.json",
            "api/compaction-checkpoint.json",
            "api/authority-fact-bundle.json",
            "api/effect-record.json",
        ] {
            let text = schema_text(name).unwrap_or_else(|e| panic!("{name}: {e}"));
            let schema: serde_json::Value =
                serde_json::from_str(&text).unwrap_or_else(|e| panic!("{name}: {e}"));
            build_validator(name, &schema)
                .unwrap_or_else(|e| panic!("{name}: not a valid schema: {e}"));
        }
    }

    // ─── SSE push events (ADR-0002 / SDK-C1) ────────────────────────────
    //
    // The committed event fixtures must validate against `api/events.json`
    // (which `$ref`s the envelope event-ref shape — no second dialect), and
    // the engine→SSE mapping table must stay complete: every engine
    // `ExecutionEvent` variant is either assigned to one of the three frozen
    // SSE names or explicitly marked not-pushed (`null`). SDK-C1 acceptance
    // criteria 2 and 4.
    #[test]
    fn events_fixtures_validate() {
        let mut found = 0;
        for name in fixture_json_names("events") {
            let json = fixture_text(&format!("events/{name}"));
            validate_schema_file("api/events.json", &json)
                .unwrap_or_else(|e| panic!("{name}: {e}"));
            found += 1;
        }
        assert!(
            found >= 3,
            "expected ≥3 committed SSE event fixtures, found {found}"
        );
    }

    #[test]
    fn events_mapping_complete() {
        let text = schema_text("api/events.json").expect("events schema");
        let events: serde_json::Value = serde_json::from_str(&text).expect("events parses");

        // 24 `ExecutionEvent` variants live in
        // `engine/src/event_system/domain/event.rs::event_type_name()`.
        let mapping = events["x-engine-event-mapping"]
            .as_object()
            .expect("x-engine-event-mapping object");
        assert_eq!(
            mapping.len(),
            24,
            "engine→SSE mapping must cover all 24 engine event variants"
        );

        let frozen = ["approval_required", "run_progress", "policy_changed"];
        for (event_type, target) in mapping {
            match target.as_str() {
                Some(name) => assert!(
                    frozen.contains(&name),
                    "{event_type} maps to unknown SSE event {name}"
                ),
                None => assert!(target.is_null(), "{event_type}: bad mapping value"),
            }
        }
        for name in frozen {
            assert!(
                mapping.values().any(|v| v.as_str() == Some(name)),
                "SSE event {name} has no engine event assigned"
            );
        }

        // The `oneOf` discriminant consts must equal the frozen event-name set.
        let mut consts: Vec<String> = Vec::new();
        for variant in events["oneOf"].as_array().expect("events oneOf") {
            let key = variant["$ref"]
                .as_str()
                .expect("variant $ref")
                .rsplit('/')
                .next()
                .expect("$defs key");
            for part in events["$defs"][key]["allOf"].as_array().expect("allOf") {
                if let Some(c) = part["properties"]["event"]["const"].as_str() {
                    consts.push(c.to_string());
                }
            }
        }
        consts.sort();
        let mut expected: Vec<String> = frozen.iter().map(|s| s.to_string()).collect();
        expected.sort();
        assert_eq!(consts, expected, "oneOf discriminant set drifted");
    }

    // ─── Native API catalog integrity (ADR-0001) ──────────────────────────
    //
    // The frozen catalog is a contract consumers build against. Guard its
    // internal consistency: unique method names, known auth/kind/stability,
    // semver `since`, and every params/result `$ref` resolving into `$defs`.
    /// The catalog inlines no identity shapes: `identityRef` / `identityClaim`
    /// live in `claims.json` and are referenced cross-file, so there is exactly
    /// one copy of each (no silent drift). Compiling the catalog proves both
    /// `$id`-addressed refs resolve offline.
    #[test]
    fn catalog_references_claims_shapes_instead_of_duplicating_them() {
        let text = schema_text("api/catalog.json").expect("catalog.json");
        let catalog: serde_json::Value = serde_json::from_str(&text).expect("catalog parses");

        let defs = catalog["$defs"].as_object().expect("$defs object");
        assert!(
            !defs.contains_key("identityRef"),
            "identityRef must not be duplicated in catalog.json — it lives in claims.json"
        );
        assert!(
            !defs.contains_key("identityClaim"),
            "identityClaim must not be duplicated in catalog.json — it lives in claims.json"
        );

        assert_eq!(
            catalog["$defs"]["validatePlanParams"]["properties"]["identity"]["$ref"],
            "https://rigorix.eu/schemas/claims.json#/$defs/identityRef"
        );
        assert_eq!(
            catalog["$defs"]["authVerifyResult"]["properties"]["claim"]["$ref"],
            "https://rigorix.eu/schemas/claims.json#/$defs/identityClaim"
        );

        // Unresolvable cross-file refs fail compilation — so this proves
        // claims.json is registered and both refs resolve offline.
        build_validator("api/catalog.json", &catalog)
            .expect("catalog compiles with claims.json registered");
    }

    #[test]
    fn catalog_integrity() {
        let text = schema_text("api/catalog.json").expect("catalog.json");
        let catalog: serde_json::Value = serde_json::from_str(&text).expect("catalog parses");

        // The catalog is DATA — validate it against its own schema document.
        let catalog_schema_text =
            schema_text("api/catalog.schema.json").expect("catalog.schema.json");
        let schema: serde_json::Value =
            serde_json::from_str(&catalog_schema_text).expect("schema parses");
        let compiled = jsonschema::validator_for(&schema).expect("catalog schema compiles");
        let errors: Vec<String> = compiled
            .iter_errors(&catalog)
            .map(|e| e.to_string())
            .collect();
        assert!(errors.is_empty(), "catalog violates its schema: {errors:?}");

        let api_version = catalog["apiVersion"].as_str().expect("apiVersion");
        assert!(
            semver_ok(api_version),
            "apiVersion must be semver, got {api_version}"
        );
        assert_eq!(catalog["jsonrpc"], "2.0");

        let defs = catalog["$defs"].as_object().expect("$defs object");
        let methods = catalog["methods"].as_array().expect("methods array");
        assert!(
            methods.len() >= 23,
            "catalog should list the frozen surface (>= 23 methods)"
        );

        let mut seen = std::collections::HashSet::new();
        for m in methods {
            let name = m["name"].as_str().expect("method name");
            assert!(name.starts_with("rigorix."), "bad namespace: {name}");
            assert!(seen.insert(name.to_string()), "duplicate method: {name}");

            assert!(
                matches!(m["kind"].as_str(), Some("query" | "command")),
                "{name}: bad kind"
            );
            assert!(
                matches!(m["auth"].as_str(), Some("public" | "session" | "admin")),
                "{name}: bad auth level"
            );
            assert!(
                matches!(
                    m["stability"].as_str(),
                    Some("frozen" | "draft" | "deprecated")
                ),
                "{name}: bad stability"
            );
            let since = m["since"].as_str().expect("since");
            assert!(semver_ok(since), "{name}: since not semver: {since}");

            for slot in ["params", "result"] {
                let reference = m[slot]["$ref"]
                    .as_str()
                    .unwrap_or_else(|| panic!("{name}: missing {slot}.$ref"));
                let key = reference.rsplit('/').next().unwrap_or_default();
                assert!(
                    defs.contains_key(key),
                    "{name}: {slot} $ref '{reference}' does not resolve in $defs"
                );
            }
        }

        // The push channel must reference the frozen events schema, and the
        // advertised event-name set must match that schema's discriminants
        // (ADR-0002 / SDK-C1).
        let push = &catalog["transport"]["push"];
        assert_eq!(push["kind"], "sse", "push kind");
        assert_eq!(push["endpoint"], "/events", "push endpoint");
        let push_schema = push["schema"].as_str().expect("transport.push.schema");
        let push_text = schema_text(push_schema).expect("push schema");
        let push_events: serde_json::Value =
            serde_json::from_str(&push_text).expect("events schema parses");
        build_validator(push_schema, &push_events).unwrap_or_else(|e| panic!("{push_schema}: {e}"));
        let mut declared: Vec<&str> = push["events"]
            .as_array()
            .expect("push.events")
            .iter()
            .map(|v| v.as_str().expect("event name"))
            .collect();
        declared.sort_unstable();
        let mut known: Vec<&str> = Vec::new();
        for variant in push_events["oneOf"].as_array().expect("events oneOf") {
            let key = variant["$ref"]
                .as_str()
                .expect("variant $ref")
                .rsplit('/')
                .next()
                .expect("$defs key");
            for part in push_events["$defs"][key]["allOf"]
                .as_array()
                .expect("allOf")
            {
                if let Some(c) = part["properties"]["event"]["const"].as_str() {
                    known.push(c);
                }
            }
        }
        known.sort_unstable();
        assert_eq!(
            declared, known,
            "catalog transport.push.events must match events.json discriminants"
        );

        // SDK-C5 / ADR-0001 D3: the closed-namespace rule is documented and the
        // previously-undeclared `rigorix.auth.verify` is now declared.
        assert!(
            catalog["description"]
                .as_str()
                .is_some_and(|d| d.contains("CLOSED")),
            "catalog.json must document the closed `rigorix.*` namespace"
        );
        let auth_verify = methods
            .iter()
            .find(|m| m["name"] == "rigorix.auth.verify")
            .expect("rigorix.auth.verify must be declared in the frozen catalog");
        assert_eq!(auth_verify["kind"], "query");
        assert_eq!(auth_verify["auth"], "session");
        assert!(
            auth_verify["mcpTool"].is_null(),
            "auth.verify is server-only"
        );
        for slot in ["params", "result"] {
            let reference = auth_verify[slot]["$ref"]
                .as_str()
                .unwrap_or_else(|| panic!("auth.verify: missing {slot}.$ref"));
            let key = reference.rsplit('/').next().unwrap_or_default();
            assert!(
                defs.contains_key(key),
                "auth.verify {slot} $ref '{reference}' does not resolve in $defs"
            );
        }

        // SDK-CATALOG-AUDIT / ADR-016 Phase B: the three ledger methods the
        // enterprise registers must be declared (query / session / no MCP tool).
        for name in [
            "rigorix.audit.head",
            "rigorix.audit.history",
            "rigorix.audit.overdue",
        ] {
            let method = methods
                .iter()
                .find(|m| m["name"] == name)
                .unwrap_or_else(|| panic!("{name} must be declared in the frozen catalog"));
            assert_eq!(method["kind"], "query", "{name}: kind");
            assert_eq!(method["auth"], "session", "{name}: auth");
            assert!(method["mcpTool"].is_null(), "{name} is server-only");
            for slot in ["params", "result"] {
                let reference = method[slot]["$ref"]
                    .as_str()
                    .unwrap_or_else(|| panic!("{name}: missing {slot}.$ref"));
                let key = reference.rsplit('/').next().unwrap_or_default();
                assert!(
                    defs.contains_key(key),
                    "{name}: {slot} $ref '{reference}' does not resolve in $defs"
                );
            }
        }
        // `audit.history` reuses the frozen history-slice shape by `$id`.
        assert_eq!(
            defs["auditHistoryResult"]["$ref"], HISTORY_SLICE_SCHEMA_ID,
            "rigorix.audit.history must reuse api/history-slice.json"
        );
    }

    // The error taxonomy and its code mapping must stay in sync: every
    // `data.type` has a code and vice versa (ADR-0001 D6).
    #[test]
    fn error_taxonomy_codes_consistent() {
        let text = schema_text("api/errors.json").expect("errors.json");
        let errors: serde_json::Value = serde_json::from_str(&text).expect("errors parses");

        let types: Vec<&str> = errors["$defs"]["errorType"]["enum"]
            .as_array()
            .expect("errorType enum")
            .iter()
            .map(|v| v.as_str().expect("string"))
            .collect();
        let codes = errors["x-error-codes"].as_object().expect("x-error-codes");

        for t in &types {
            assert!(codes.contains_key(*t), "error type '{t}' has no code");
        }
        for key in codes.keys() {
            assert!(
                types.contains(&key.as_str()),
                "code mapping '{key}' is not a declared error type"
            );
        }
    }

    // ─── ADR-016 audit integrity (SDK-AUDIT-A / #12) ─────────────────────
    //
    // The chained fixtures are produced by the REAL rigorix-oss engine
    // (ADR-016 Phase A, #902) with the fixed fixture key. The anchor artifacts
    // (receipt / slice / checkpoint) have no anchor implementation yet — they
    // are contract fixtures signed with a deterministic TEST-ONLY Ed25519 key
    // (see `generate_anchor_fixtures`).
    const FIXTURE_KEY: &str = "fixture-hmac-key-2026";
    /// Deterministic TEST-ONLY Ed25519 seed (never a production key).
    const ANCHOR_SECRET: [u8; 32] = [7u8; 32];

    fn anchor_signing_key() -> ed25519_dalek::SigningKey {
        ed25519_dalek::SigningKey::from_bytes(&ANCHOR_SECRET)
    }

    fn anchor_public_hex() -> String {
        hex::encode(anchor_signing_key().verifying_key().to_bytes())
    }

    /// Where the ignored `generate_anchor_fixtures` writes (repo checkout only).
    fn integrity_dir() -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../schemas/fixtures/integrity")
    }

    /// Read a fixture through the published resolution path (env -> embedded).
    fn read_envelopes(name: &str) -> Vec<AuditEnvelope> {
        let text = read_json(name);
        serde_json::from_str(&text).unwrap_or_else(|e| panic!("{name}: {e}"))
    }

    fn read_json(name: &str) -> String {
        fixture_text(&format!("integrity/{name}"))
    }

    /// The standalone guarantee (SDK-VERIFIER-PUBLISH): with no
    /// `RIGORIX_SDK_SCHEMAS`, every contract entry point resolves from the
    /// embedded `rigorix-schemas` corpus — signature, catalog subset, chain.
    #[test]
    fn embedded_corpus_smoke() {
        let json = fixture_text("envelope/envelope-minimal-signed.json");
        verify_signature(&json, FIXTURE_KEY).expect("embedded engine fixture verifies");
        verify_catalog_subset(&["rigorix.plan", "rigorix.auth.verify"])
            .expect("embedded catalog contains the declared subset");
        let chain = read_envelopes("chain.json");
        verify_chain(&chain).expect("embedded chain verifies");
    }

    #[test]
    fn integrity_chain_fixtures_verify() {
        let envelopes = read_envelopes("chain.json");
        assert!(envelopes.len() >= 3, "expected a >=3-envelope chain");

        // Each engine-signed envelope verifies byte-exact (HMAC) + conforms to
        // envelope.json (which now carries the ADR-016 chain fields).
        let values: Vec<serde_json::Value> =
            serde_json::from_str(&read_json("chain.json")).expect("chain array parses");
        for value in &values {
            let one = value.to_string();
            verify_signature(&one, FIXTURE_KEY).unwrap_or_else(|e| panic!("fixture hmac: {e}"));
            validate_schema(&one).unwrap_or_else(|e| panic!("envelope schema: {e}"));
        }

        // Chain continuity: genesis 0, contiguous, prev_hash links.
        verify_chain(&envelopes).expect("valid chain must verify");
        assert!(envelopes
            .iter()
            .all(|e| e.history_integrity == Some(HistoryIntegrity::LocalUnanchored)));
        for pair in envelopes.windows(2) {
            assert_eq!(
                Some(envelope_hash_of(&pair[0]).unwrap()),
                pair[1].prev_hash,
                "prev_hash must be the predecessor's canonical hash"
            );
        }
        assert_eq!(envelopes[0].sequence, Some(0));
        assert!(envelopes[0].prev_hash.is_none(), "genesis has no prev_hash");
    }

    #[test]
    fn integrity_broken_chain_is_rejected() {
        let envelopes = read_envelopes("broken-chain.json");
        let err = verify_chain(&envelopes).expect_err("an uncovered gap must fail");
        assert!(matches!(err, VerifyError::ChainBroken { .. }), "{err:?}");
    }

    #[test]
    fn chain_detects_altered_predecessor_and_duplicate_sequence() {
        // An altered predecessor link (prev_hash no longer matches the hash).
        let mut envelopes = read_envelopes("chain.json");
        envelopes[2].prev_hash = Some("0".repeat(64));
        let err = verify_chain(&envelopes).expect_err("altered prev_hash must fail");
        assert!(matches!(err, VerifyError::ChainBroken { .. }), "{err:?}");

        // A duplicated sequence number (insertion).
        let mut envelopes = read_envelopes("chain.json");
        envelopes[2].sequence = Some(1);
        let err = verify_chain(&envelopes).expect_err("duplicate sequence must fail");
        assert!(matches!(err, VerifyError::ChainBroken { .. }), "{err:?}");
    }

    #[test]
    fn checkpoint_covers_broken_chain_gap() {
        let envelopes = read_envelopes("broken-chain.json");
        let text = read_json("compaction-checkpoint.json");
        let checkpoint: CompactionCheckpoint = serde_json::from_str(&text).expect("checkpoint");

        // Strict verification fails; the signed checkpoint covers the gap.
        assert!(verify_chain(&envelopes).is_err());
        verify_chain_with_checkpoints(
            &envelopes,
            std::slice::from_ref(&checkpoint),
            &anchor_public_hex(),
        )
        .expect("a checkpoint-covered gap must verify");
        validate_schema_file("api/compaction-checkpoint.json", &text).expect("checkpoint schema");

        // A forged checkpoint (wrong new_head, re-signed with a different key)
        // neither verifies nor covers the gap.
        let mut forged = checkpoint.clone();
        forged.new_head = "0".repeat(64);
        assert!(verify_chain_with_checkpoints(
            &envelopes,
            std::slice::from_ref(&forged),
            &anchor_public_hex()
        )
        .is_err());
    }

    #[test]
    fn history_slice_fixture_verifies() {
        let text = read_json("history-slice.json");
        let slice: HistorySlice = serde_json::from_str(&text).expect("slice parses");
        verify_history_slice(&slice, &anchor_public_hex()).expect("anchor signature");
        validate_schema_file("api/history-slice.json", &text).expect("history-slice schema");
        assert!(!slice.actions.is_empty(), "slice carries prior actions");

        // A forged slice (tampered action) is rejected.
        let mut forged = slice.clone();
        forged.actions[0].node = "forged_node".to_string();
        assert!(verify_history_slice(&forged, &anchor_public_hex()).is_err());
    }

    #[test]
    fn ledger_receipt_fixture_verifies() {
        let text = read_json("ledger-receipt.json");
        let receipt: LedgerReceipt = serde_json::from_str(&text).expect("receipt parses");
        verify_ledger_receipt(&receipt, &anchor_public_hex()).expect("anchor signature");
        validate_schema_file("api/ledger-receipt.json", &text).expect("ledger-receipt schema");

        let mut forged = receipt.clone();
        forged.envelope_hash = "0".repeat(64);
        assert!(verify_ledger_receipt(&forged, &anchor_public_hex()).is_err());
    }

    // ─── Effect commitment artifact (ADR-019 / SDK 0.7.0) ────────────────
    //
    // Contract-first fixtures: the engine does not emit this artifact yet, so
    // the read-back bodies are fixed inputs and the digests are recomputed by
    // `verify_settlement_evidence` exactly as the engine computes them.

    fn read_effect(name: &str) -> (String, EffectRecordArtifact) {
        let text = fixture_text(&format!("effect/{name}"));
        let artifact: EffectRecordArtifact =
            serde_json::from_str(&text).unwrap_or_else(|e| panic!("{name}: {e}"));
        (text, artifact)
    }

    /// The accepted fixture set is pinned exactly: deleting a fixture or adding
    /// an unverified one fails. A lower-bound count (`>= 5`) would let the loop
    /// silently shrink, which is the same defect as an unpinned rejection.
    const ACCEPTED_EFFECT_FIXTURES: &[&str] = &[
        "ambiguous-unsettled.json",
        "committed-l1-l3.json",
        "dispatched-with-deadline.json",
        "not-committed-l2-l3.json",
        "resolved-ambiguous.json",
    ];

    /// Where a rejected fixture must be stopped. `Schema` cases are also
    /// asserted to fail the structural verifier, so the independent re-check is
    /// exercised even when the schema catches the violation first.
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    enum RejectionLayer {
        Schema,
        Structural,
        ReadbackDigestMismatch,
        ReadbackMissing,
    }

    /// Every rejected fixture, and the layer that must reject it. This table and
    /// the `rejected-*.json` files must be equal as sets: a fixture without a
    /// case is inert coverage, and a case without a fixture is a stale claim.
    const REJECTED_EFFECT_FIXTURES: &[(&str, RejectionLayer)] = &[
        (
            "rejected-terminal-without-evidence.json",
            RejectionLayer::Schema,
        ),
        (
            "rejected-nonterminal-with-settlement.json",
            RejectionLayer::Schema,
        ),
        (
            "rejected-dispatched-without-deadline.json",
            RejectionLayer::Schema,
        ),
        ("rejected-verdict-mismatch.json", RejectionLayer::Schema),
        (
            "rejected-readback-mismatch.json",
            RejectionLayer::ReadbackDigestMismatch,
        ),
        (
            "rejected-readback-missing.json",
            RejectionLayer::ReadbackMissing,
        ),
        (
            "rejected-settlement-with-none-level.json",
            RejectionLayer::Structural,
        ),
    ];

    fn accepted_fixture_names() -> Vec<String> {
        fixture_json_names("effect")
            .into_iter()
            .filter(|name| !name.starts_with("rejected-"))
            .collect()
    }

    fn rejected_fixture_names() -> Vec<String> {
        fixture_json_names("effect")
            .into_iter()
            .filter(|name| name.starts_with("rejected-"))
            .collect()
    }

    fn sorted(mut names: Vec<String>) -> Vec<String> {
        names.sort();
        names
    }

    /// Every accepted fixture is pinned, validates against the frozen schema,
    /// and passes both verification levels (readback only when bytes are present).
    #[test]
    fn effect_record_fixtures_verify() {
        let on_disk = sorted(accepted_fixture_names());
        let pinned: Vec<String> = ACCEPTED_EFFECT_FIXTURES
            .iter()
            .map(|name| (*name).to_string())
            .collect();
        assert_eq!(
            on_disk,
            sorted(pinned),
            "every accepted fixture must be pinned and every pinned fixture must exist"
        );

        for name in ACCEPTED_EFFECT_FIXTURES {
            let (text, artifact) = read_effect(name);
            validate_schema_file("api/effect-record.json", &text)
                .unwrap_or_else(|e| panic!("{name}: schema: {e}"));
            verify_effect_record(&artifact).unwrap_or_else(|e| panic!("{name}: structural: {e}"));
            if artifact
                .settlement
                .as_ref()
                .is_some_and(|s| s.readback.is_some())
            {
                verify_settlement_evidence(&artifact)
                    .unwrap_or_else(|e| panic!("{name}: readback: {e}"));
            }
        }
    }

    /// The two axes are independent: `l1` durability + `l3` settlement is legal
    /// and must round-trip. This is the #1182 regression in schema form.
    #[test]
    fn effect_record_keeps_durability_and_settlement_orthogonal() {
        let (_, artifact) = read_effect("committed-l1-l3.json");
        assert_eq!(artifact.levels.durability, Durability::L1);
        assert_eq!(artifact.levels.settlement, SettlementLevel::L3);
        verify_settlement_evidence(&artifact).expect("valid l1 + l3 artifact");
    }

    /// Every rejected fixture is pinned to a case, and every case rejects at the
    /// layer it claims. Adding `rejected-zzz-probe.json` without a case fails
    /// the set equality below; adding a case without a fixture fails too.
    #[test]
    fn effect_record_rejected_fixtures_are_pinned_and_rejected() {
        let on_disk = sorted(rejected_fixture_names());
        let pinned: Vec<String> = REJECTED_EFFECT_FIXTURES
            .iter()
            .map(|(name, _)| (*name).to_string())
            .collect();
        assert_eq!(
            on_disk,
            sorted(pinned),
            "every rejected fixture must have a case and every case must have a fixture"
        );

        for (name, layer) in REJECTED_EFFECT_FIXTURES {
            let (text, artifact) = read_effect(name);

            let schema = validate_schema_file("api/effect-record.json", &text);
            let structural = verify_effect_record(&artifact);

            match layer {
                RejectionLayer::Schema => {
                    assert!(schema.is_err(), "{name}: schema must reject");
                    let err = structural.expect_err("structural must also reject");
                    assert!(
                        matches!(err, VerifyError::EffectInvariant { .. }),
                        "{name}: {err:?}"
                    );
                }
                RejectionLayer::Structural => {
                    schema.unwrap_or_else(|e| panic!("{name}: schema should accept: {e}"));
                    let err = structural.expect_err("structural must reject");
                    assert!(
                        matches!(err, VerifyError::EffectInvariant { .. }),
                        "{name}: {err:?}"
                    );
                }
                RejectionLayer::ReadbackDigestMismatch => {
                    schema.unwrap_or_else(|e| panic!("{name}: schema should accept: {e}"));
                    structural.unwrap_or_else(|e| panic!("{name}: structural should accept: {e}"));
                    let err = verify_settlement_evidence(&artifact)
                        .expect_err("readback digest must not match");
                    assert!(
                        matches!(err, VerifyError::ReadbackDigestMismatch { .. }),
                        "{name}: {err:?}"
                    );
                }
                RejectionLayer::ReadbackMissing => {
                    schema.unwrap_or_else(|e| panic!("{name}: schema should accept: {e}"));
                    structural.unwrap_or_else(|e| panic!("{name}: structural should accept: {e}"));
                    let err = verify_settlement_evidence(&artifact)
                        .expect_err("readback bytes must be required");
                    assert!(
                        matches!(err, VerifyError::ReadbackMissing),
                        "{name}: {err:?}"
                    );
                }
            }
        }
    }

    /// Regenerates the three anchor-artifact fixtures. The envelope chain
    /// fixtures are engine-produced and must NOT be regenerated here.
    #[test]
    #[ignore = "fixture generator — run with --ignored to regenerate anchor fixtures"]
    fn generate_anchor_fixtures() {
        use ed25519_dalek::Signer;

        let key = anchor_signing_key();
        let dir = integrity_dir();
        let chain = read_envelopes("chain.json");
        let head = chain.last().expect("chain non-empty");

        // History slice over the chain's actions.
        let mut slice = HistorySlice {
            scope: "local".to_string(),
            since: chain[0].timestamp,
            actions: chain
                .iter()
                .flat_map(|envelope| {
                    envelope.events.iter().filter_map(|event| {
                        let node = event
                            .payload
                            .as_ref()?
                            .get("step_name")?
                            .as_str()?
                            .to_string();
                        Some(HistoryActionRef {
                            node,
                            principal: envelope.author.clone(),
                            at: event.occurred_at,
                            effect_key: envelope.effect_key.clone(),
                        })
                    })
                })
                .collect(),
            head_hash: envelope_hash_of(head).expect("head hash"),
            sig: None,
        };
        let bytes = history_slice_signing_bytes(&slice).expect("slice bytes");
        slice.sig = Some(hex::encode(key.sign(&bytes).to_bytes()));
        std::fs::write(
            dir.join("history-slice.json"),
            format!("{}\n", serde_json::to_string_pretty(&slice).unwrap()),
        )
        .expect("write history slice");

        // Ledger receipt for the chain head.
        let mut receipt = LedgerReceipt {
            ledger_id: "local-ledger".to_string(),
            envelope_hash: envelope_hash_of(head).expect("head hash"),
            sequence: head.sequence.expect("head sequence"),
            recorded_at: head.timestamp,
            sig: None,
        };
        let bytes = ledger_receipt_signing_bytes(&receipt).expect("receipt bytes");
        receipt.sig = Some(hex::encode(key.sign(&bytes).to_bytes()));
        std::fs::write(
            dir.join("ledger-receipt.json"),
            format!("{}\n", serde_json::to_string_pretty(&receipt).unwrap()),
        )
        .expect("write ledger receipt");

        // Compaction checkpoint covering the broken-chain gap (seq 1..=1).
        let broken = read_envelopes("broken-chain.json");
        let after = &broken[1];
        let mut checkpoint = CompactionCheckpoint {
            sequence_from: 1,
            sequence_to: 1,
            reason: "gdpr-erasure".to_string(),
            prior_head: envelope_hash_of(&broken[0]).expect("prior hash"),
            new_head: after.prev_hash.clone().expect("successor link"),
            sig: None,
        };
        let bytes = compaction_checkpoint_signing_bytes(&checkpoint).expect("checkpoint bytes");
        checkpoint.sig = Some(hex::encode(key.sign(&bytes).to_bytes()));
        std::fs::write(
            dir.join("compaction-checkpoint.json"),
            format!("{}\n", serde_json::to_string_pretty(&checkpoint).unwrap()),
        )
        .expect("write compaction checkpoint");
    }

    // ─── Catalog parity / closed namespace (ADR-0001 D3; SDK-C5 #15,
    //     SDK-CATALOG-AUDIT #20) ────────────────────────────────────────
    //
    // Every method a server registers must be declared in the frozen catalog;
    // a server implements a SUBSET, never an extension. The enterprise
    // Execution API's 13-method set is the canonical positive case.
    #[test]
    fn catalog_subset_guard_rejects_undeclared_method() {
        let enterprise = [
            "rigorix.plan",
            "rigorix.validatePlan",
            "rigorix.run",
            "rigorix.approve",
            "rigorix.auth.verify",
            "rigorix.policy.bundle",
            "rigorix.audit.read",
            "rigorix.audit.list",
            "rigorix.audit.summary",
            "rigorix.audit.head",
            "rigorix.audit.history",
            "rigorix.audit.overdue",
            "rigorix.system.version",
        ];
        verify_catalog_subset(&enterprise).expect("a declared subset must pass");

        let err = verify_catalog_subset(&["rigorix.auth.bogus"]).unwrap_err();
        assert!(
            matches!(err, VerifyError::UndeclaredMethod(ref m) if m == "rigorix.auth.bogus"),
            "{err:?}"
        );
    }

    // The consequence-gating §4.3 catalog addition (SDK #44): the method is
    // declared with the frozen shape, its result is the STANDALONE bundle file
    // (not an inline shape), and that bundle `$ref`s the one canonical envelope
    // dialect — no second envelope shape. Additive within the closed namespace.
    #[test]
    fn catalog_declares_authority_fact_projection_additively() {
        let text = schema_text("api/catalog.json").expect("catalog.json");
        let catalog: serde_json::Value = serde_json::from_str(&text).expect("catalog parses");
        let method = catalog["methods"]
            .as_array()
            .expect("methods")
            .iter()
            .find(|m| m["name"] == "rigorix.audit.authorityFacts")
            .expect("rigorix.audit.authorityFacts must be declared");
        assert_eq!(method["kind"], "query");
        assert_eq!(
            method["auth"], "session",
            "an OSS capability is a session method, not an enterprise (admin) scope"
        );
        assert_eq!(method["mcpTool"], "rigorix_audit_authority_facts");
        assert_eq!(method["params"]["$ref"], "#/$defs/authorityFactsParams");
        assert_eq!(method["result"]["$ref"], "#/$defs/authorityFactsResult");

        // `authorityFactsResult` addresses the standalone bundle by `$id`; the
        // catalog's `$defs` hold method-local shapes, and canonical artifacts
        // are standalone files with an `$id` (as with `auditHistoryResult`).
        assert_eq!(
            catalog["$defs"]["authorityFactsResult"]["$ref"],
            AUTHORITY_FACT_BUNDLE_SCHEMA_ID
        );

        // The bundle's `envelopes[]` is the ONE canonical envelope dialect.
        let bundle_text = schema_text("api/authority-fact-bundle.json").expect("bundle schema");
        let bundle: serde_json::Value = serde_json::from_str(&bundle_text).expect("bundle parses");
        assert_eq!(
            bundle["properties"]["envelopes"]["items"]["$ref"], ENVELOPE_SCHEMA_ID,
            "the bundle must $ref envelope.json (no second envelope dialect)"
        );

        // The new name is a declared subset member (a server may serve it).
        verify_catalog_subset(&["rigorix.audit.authorityFacts"])
            .expect("the projection method must be a declared subset member");
    }

    fn semver_ok(s: &str) -> bool {
        let parts: Vec<&str> = s.split('.').collect();
        parts.len() == 3 && parts.iter().all(|p| p.parse::<u64>().is_ok())
    }

    /// #1222: `scope_check` is part of the envelope dialect. Unknown fields are
    /// dropped on re-serialization, so a verifier that lacks the field produces
    /// different canonical bytes and rejects a correctly signed envelope.
    #[test]
    fn scope_check_survives_canonicalization() {
        let raw = r#"{
            "execution_id": "8c1d5eac-8935-4960-82cf-199df61d2539",
            "timestamp": "2026-10-30T12:00:00Z",
            "template_id": "t",
            "planning_hash": "h",
            "total_tokens": 0,
            "duration_ms": 0,
            "events": [],
            "signature": null,
            "evidence_degraded": false,
            "scope_check": "checked"
        }"#;
        let envelope: AuditEnvelope = serde_json::from_str(raw).expect("parse");
        assert_eq!(envelope.scope_check, Some(ScopeCheckStatus::Checked));
        let canonical = String::from_utf8(canonical_bytes(raw).expect("canonical")).expect("utf8");
        assert!(
            canonical.contains(r#""scope_check":"checked""#),
            "the field must be in the signed bytes: {canonical}"
        );
    }
}
