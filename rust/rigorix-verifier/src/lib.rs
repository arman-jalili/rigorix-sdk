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
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub approval_events: Vec<ApprovalRecordRef>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub scope_violations: Vec<ScopeViolationRef>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub sequence_policy_findings: Vec<SequencePolicyFindingRef>,
    /// R9/ADR-015 operator step-requirement findings. MUST stay after
    /// `sequence_policy_findings` and before `decision_context_ref`.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub requirement_findings: Vec<RequirementFindingRef>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub decision_context_ref: Option<String>,
}

/// ADR-016: which integrity regime produced an envelope's evidence.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HistoryIntegrity {
    /// Local cache only — tamper-evident, not anchor-authenticated.
    LocalUnanchored,
    /// Anchor-authenticated evidence (Phase C).
    Anchored,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApprovalRecordRef {
    pub node_id: uuid::Uuid,
    pub step_name: String,
    pub intent_hash: String,
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
/// The schema path resolves from `RIGORIX_SDK_SCHEMAS` env (CI/local override)
/// or defaults to `../../schemas` relative to this crate.
pub fn validate_schema(json: &str) -> VerifyResult<()> {
    validate_schema_file("envelope.json", json)
}

/// Validate any JSON instance against a named SDK schema file.
fn validate_schema_file(file: &str, json: &str) -> VerifyResult<()> {
    let schema_path = schema_path(file)?;
    let schema_text = std::fs::read_to_string(&schema_path)
        .map_err(|e| VerifyError::SchemaRead(format!("{}: {e}", schema_path.display())))?;
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

fn schema_path(file: &str) -> VerifyResult<std::path::PathBuf> {
    if let Ok(dir) = std::env::var("RIGORIX_SDK_SCHEMAS") {
        let p = Path::new(&dir).join(file);
        if p.exists() {
            return Ok(p);
        }
        return Err(VerifyError::SchemaRead(format!(
            "RIGORIX_SDK_SCHEMAS set but {} missing",
            p.display()
        )));
    }
    let p = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../schemas")
        .join(file);
    if p.exists() {
        Ok(p)
    } else {
        Err(VerifyError::SchemaRead(format!(
            "schema not found at {} — set RIGORIX_SDK_SCHEMAS",
            p.display()
        )))
    }
}

/// The `$id` of the canonical envelope schema — the only cross-file `$ref`
/// target on the contract surface (`api/events.json` → `envelope.json`).
const ENVELOPE_SCHEMA_ID: &str = "https://rigorix.dev/schemas/envelope-v2.json";

/// Build a JSON Schema validator, registering sibling contract schemas so
/// cross-file `$ref`s (e.g. `events.json` → `envelope.json`) resolve offline.
fn build_validator(file: &str, schema: &serde_json::Value) -> VerifyResult<jsonschema::Validator> {
    // The envelope schema is the only external `$ref` target today. Register it
    // under its `$id` unless we are compiling the envelope itself.
    if file == "envelope.json" {
        return jsonschema::validator_for(schema).map_err(|e| VerifyError::Schema(e.to_string()));
    }
    let envelope_path = schema_path("envelope.json")?;
    let envelope_text = std::fs::read_to_string(&envelope_path)
        .map_err(|e| VerifyError::SchemaRead(format!("{}: {e}", envelope_path.display())))?;
    let envelope: serde_json::Value = serde_json::from_str(&envelope_text)?;
    let resource = jsonschema::Resource::from_contents(envelope)
        .map_err(|e| VerifyError::Schema(e.to_string()))?;
    jsonschema::options()
        .with_resource(ENVELOPE_SCHEMA_ID, resource)
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
        let fixtures_dir =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../schemas/fixtures/envelope");
        let mut found = 0;
        let entries = std::fs::read_dir(&fixtures_dir)
            .unwrap_or_else(|e| panic!("read {}: {e}", fixtures_dir.display()));
        for entry in entries {
            let path = entry.expect("dir entry").path();
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                continue;
            }
            let json = std::fs::read_to_string(&path)
                .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
            // Independent verifier accepts the engine's signature byte-exact.
            verify_signature(&json, key).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
            // And the envelope conforms to the SDK schema.
            validate_schema(&json).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
            found += 1;
        }
        assert!(
            found >= 3,
            "expected ≥3 committed engine fixtures, found {found} in {}",
            fixtures_dir.display()
        );
    }

    // ─── Schema lint (SDK contract surface) ───────────────────────────────
    //
    // Every top-level contract schema must be a well-formed JSON Schema
    // (draft 2020-12) that compiles cleanly. This is the SDK's own guard that
    // the published contract surface never ships a broken schema.
    #[test]
    fn all_schemas_compile() {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../schemas");
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
        ] {
            let path = dir.join(name);
            let text = std::fs::read_to_string(&path)
                .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
            let schema: serde_json::Value =
                serde_json::from_str(&text).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
            build_validator(name, &schema)
                .unwrap_or_else(|e| panic!("{}: not a valid schema: {e}", path.display()));
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
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../schemas/fixtures/events");
        let entries =
            std::fs::read_dir(&dir).unwrap_or_else(|e| panic!("read {}: {e}", dir.display()));
        let mut found = 0;
        for entry in entries {
            let path = entry.expect("dir entry").path();
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                continue;
            }
            let json = std::fs::read_to_string(&path)
                .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
            validate_schema_file("api/events.json", &json)
                .unwrap_or_else(|e| panic!("{}: {e}", path.display()));
            found += 1;
        }
        assert!(
            found >= 3,
            "expected ≥3 committed SSE event fixtures, found {found} in {}",
            dir.display()
        );
    }

    #[test]
    fn events_mapping_complete() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../schemas/api/events.json");
        let text = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
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
    #[test]
    fn catalog_integrity() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../schemas/api/catalog.json");
        let text = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        let catalog: serde_json::Value = serde_json::from_str(&text).expect("catalog parses");

        // The catalog is DATA — validate it against its own schema document.
        let schema_path =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../schemas/api/catalog.schema.json");
        let schema_text = std::fs::read_to_string(&schema_path)
            .unwrap_or_else(|e| panic!("read {}: {e}", schema_path.display()));
        let schema: serde_json::Value = serde_json::from_str(&schema_text).expect("schema parses");
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
            methods.len() >= 19,
            "catalog should list the frozen surface"
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
        let push_path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../schemas")
            .join(push_schema);
        let push_text = std::fs::read_to_string(&push_path)
            .unwrap_or_else(|e| panic!("read {}: {e}", push_path.display()));
        let push_events: serde_json::Value =
            serde_json::from_str(&push_text).expect("events schema parses");
        build_validator(push_schema, &push_events)
            .unwrap_or_else(|e| panic!("{}: {e}", push_path.display()));
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
    }

    // The error taxonomy and its code mapping must stay in sync: every
    // `data.type` has a code and vice versa (ADR-0001 D6).
    #[test]
    fn error_taxonomy_codes_consistent() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../schemas/api/errors.json");
        let text = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
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

    fn integrity_dir() -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../schemas/fixtures/integrity")
    }

    fn read_envelopes(name: &str) -> Vec<AuditEnvelope> {
        let path = integrity_dir().join(name);
        let text = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        serde_json::from_str(&text).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
    }

    fn read_json(name: &str) -> String {
        let path = integrity_dir().join(name);
        std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
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

    fn semver_ok(s: &str) -> bool {
        let parts: Vec<&str> = s.split('.').collect();
        parts.len() == 3 && parts.iter().all(|p| p.parse::<u64>().is_ok())
    }
}
