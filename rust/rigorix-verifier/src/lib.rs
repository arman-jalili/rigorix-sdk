//! rigorix-verifier — protocol-only verification of Rigorix audit envelopes.
//!
//! Strategy A (SDK freeze D-2): the HMAC trail must be independently
//! checkable anywhere — this crate verifies envelopes WITHOUT depending on
//! rigorix-engine. The envelope structs below are FROZEN copies of
//! rigorix-oss `engine/src/audit/domain/envelope.rs` + the redacted identity
//! ref from `identity/domain/claim.rs` (contract freeze: do not edit them to
//! match engine internals; edit them only when the SDK schemas change).
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
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::Sha256;

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
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub approval_events: Vec<ApprovalRecordRef>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub scope_violations: Vec<ScopeViolationRef>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub sequence_policy_findings: Vec<SequencePolicyFindingRef>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub decision_context_ref: Option<String>,
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
    let mut envelope: AuditEnvelope = serde_json::from_str(json)?;
    envelope.signature = None;
    Ok(serde_json::to_vec(&envelope)?)
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
    let compiled =
        jsonschema::validator_for(&schema).map_err(|e| VerifyError::Schema(e.to_string()))?;
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
        ] {
            let path = dir.join(name);
            let text = std::fs::read_to_string(&path)
                .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
            let schema: serde_json::Value =
                serde_json::from_str(&text).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
            jsonschema::validator_for(&schema)
                .unwrap_or_else(|e| panic!("{}: not a valid schema: {e}", path.display()));
        }
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

    fn semver_ok(s: &str) -> bool {
        let parts: Vec<&str> = s.split('.').collect();
        parts.len() == 3 && parts.iter().all(|p| p.parse::<u64>().is_ok())
    }
}
