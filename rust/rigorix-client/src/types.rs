//! Typed request/result structs mirroring `schemas/api/catalog.json` `$defs`
//! (ADR-0001). Field names match the frozen catalog exactly (serde snake_case).
//!
//! Open subtrees (a plan, enforcement details, a step's `parameters`, template
//! `steps`) are carried as [`serde_json::Value`]; everything with a stable
//! shape is a typed struct.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// `emptyParams`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct EmptyParams {}

/// `planParams`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanParams {
    pub template_name: String,
}

/// `planResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanResult {
    pub template_name: String,
    pub description: String,
    pub version: String,
    pub tags: Vec<String>,
    pub graph: Value,
    #[serde(default)]
    pub constraints: Option<Constraints>,
    pub enforcement: Value,
}

/// `constraints`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Constraints {
    #[serde(default)]
    pub max_tool_calls: Option<u64>,
    #[serde(default)]
    pub max_tokens: Option<u64>,
    #[serde(default)]
    pub max_duration_secs: Option<u64>,
    #[serde(default)]
    pub blocked_tools: Vec<String>,
    #[serde(default)]
    pub extensions: HashMap<String, String>,
}

/// `validatePlanParams`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidatePlanParams {
    pub plan: Value,
    #[serde(default)]
    pub identity: Option<Value>,
}

/// `validateResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidateResult {
    pub valid: bool,
    #[serde(default)]
    pub warnings: Vec<String>,
    #[serde(default)]
    pub errors: Vec<String>,
    #[serde(default)]
    pub estimated_cost: Option<CostEstimate>,
}

/// `costEstimate`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CostEstimate {
    pub estimated_tokens: u64,
    pub estimated_tool_calls: u64,
    #[serde(default)]
    pub estimated_cost_micro: Option<u64>,
}

/// `runParams`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunParams {
    pub template_name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub execution_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub repository: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub author: Option<String>,
}

/// `executeParams`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ExecuteParams {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub plan: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub template_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub execution_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub repository: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub author: Option<String>,
}

/// `executeResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecuteResult {
    pub execution_id: String,
    pub status: String,
    pub steps: Vec<StepResult>,
    pub duration_ms: u64,
    #[serde(default)]
    pub tokens_used: Option<u64>,
    pub audit_uri: String,
}

/// `stepResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StepResult {
    pub step_name: String,
    pub success: bool,
    #[serde(default)]
    pub error: Option<String>,
    #[serde(default)]
    pub output: Option<Value>,
    pub duration_ms: u64,
}

/// `approveParams`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApproveParams {
    pub execution_id: String,
    pub step_names: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub approver_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub authority: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub token_claims_ref: Option<String>,
}

/// `approveResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApproveResult {
    pub execution_id: String,
    pub approved_steps: Vec<String>,
    pub not_found: Vec<String>,
    pub still_pending: Vec<String>,
    pub resumed: bool,
    pub message: String,
    #[serde(default)]
    pub final_state: Option<String>,
}

/// `checkEnforcementResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CheckEnforcementResult {
    pub active: bool,
    pub preset: String,
    pub budget: BudgetStatus,
    pub circuit_breakers: Vec<CircuitBreaker>,
}

/// `checkEnforcementResult.budget`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BudgetStatus {
    pub tool_calls_total: u64,
    pub tool_calls_remaining: u64,
    pub tokens_total: u64,
    pub tokens_remaining: u64,
}

/// `checkEnforcementResult.circuit_breakers[]`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CircuitBreaker {
    pub name: String,
    pub is_tripped: bool,
    pub description: String,
}

/// `auditReadParams`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditReadParams {
    pub execution_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub format: Option<String>,
}

/// `auditReadResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditReadResult {
    pub execution_id: String,
    pub status: String,
    #[serde(default)]
    pub template_name: Option<String>,
    pub started_at: String,
    pub completed_at: String,
    pub duration_ms: u64,
    pub steps: Vec<StepResult>,
    #[serde(default)]
    pub tokens_used: Option<u64>,
    pub audit_uri: String,
}

/// `auditListParams`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AuditListParams {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub since: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub until: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub template: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub limit: Option<u32>,
}

/// `auditListResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditListResult {
    pub total_count: u64,
    pub audits: Vec<AuditListItem>,
}

/// `auditListResult.audits[]`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditListItem {
    pub execution_id: String,
    pub status: String,
    #[serde(default)]
    pub template_name: Option<String>,
    pub started_at: String,
    pub duration_ms: u64,
    pub audit_uri: String,
}

/// `auditSummaryParams`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AuditSummaryParams {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub since: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub until: Option<String>,
}

/// `auditSummaryResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditSummaryResult {
    pub since: String,
    pub until: String,
    pub total_executions: u64,
    pub success_count: u64,
    pub failure_count: u64,
    pub success_rate: f64,
    pub total_duration_ms: u64,
    #[serde(default)]
    pub total_tokens: Option<u64>,
    pub top_failures: Vec<TopFailure>,
    pub top_templates: Vec<TopTemplate>,
}

/// `auditSummaryResult.top_failures[]`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TopFailure {
    pub description: String,
    pub count: u64,
    #[serde(default)]
    pub template_name: Option<String>,
}

/// `auditSummaryResult.top_templates[]`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TopTemplate {
    pub name: String,
    pub count: u64,
    pub avg_duration_ms: u64,
}

/// `templateListParams`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TemplateListParams {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub limit: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub search: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
}

/// `templateListResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateListResult {
    pub templates: Vec<TemplateListItem>,
}

/// `templateListResult.templates[]`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateListItem {
    pub name: String,
    pub description: String,
    pub version: String,
    pub tags: Vec<String>,
    pub step_count: u64,
    pub updated_at: String,
}

/// `templateGetParams`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateGetParams {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub format: Option<String>,
}

/// `templateGetResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateGetResult {
    pub name: String,
    pub description: String,
    pub version: String,
    pub tags: Vec<String>,
    pub steps: Vec<Value>,
    #[serde(default)]
    pub constraints: Option<Constraints>,
    #[serde(default)]
    pub metadata: Option<HashMap<String, String>>,
    pub created_at: String,
    pub updated_at: String,
}

/// `templateCreateParams`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateCreateParams {
    pub name: String,
    pub plan: Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub overwrite: Option<bool>,
}

/// `templateCreateResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateCreateResult {
    pub name: String,
    pub path: String,
    pub status: String,
}

/// `templateValidateParams`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateValidateParams {
    pub plan: Value,
}

/// `authLoginParams`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AuthLoginParams {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub client_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub issuer: Option<String>,
}

/// `authLoginResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthLoginResult {
    pub status: String,
    pub verification_uri: String,
    pub user_code: String,
    pub expires_in: u64,
}

/// `authStatusResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthStatusResult {
    pub status: String,
    #[serde(default)]
    pub claim_summary: Option<ClaimSummary>,
    pub source: String,
}

/// `claimSummary`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClaimSummary {
    pub subject: String,
    pub issuer: String,
    #[serde(default)]
    pub authority: Option<String>,
    #[serde(default)]
    pub expires_at: Option<String>,
}

/// `authLogoutResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthLogoutResult {
    pub status: String,
}

/// `usageGuideResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UsageGuideResult {
    pub guide: String,
}

/// `versionResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VersionResult {
    pub name: String,
    pub engine_version: String,
    pub api_version: String,
    pub schemas: Vec<String>,
    pub capabilities: Vec<String>,
}
