"""Frozen `rigorix.*` catalog binding table and typed DTO shapes.

The 18 typed methods mirror ``typescript-client/src/client.ts``; the DTOs mirror
``schemas/api/catalog.json`` ``$defs``. The six server-only methods are recorded
with a reason so the parity test can prove none is silently omitted. There is
deliberately no raw step-execution method (ADR-0001 D10).
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, TypedDict

CLIENT_API_MAJOR = 1
CLIENT_API_VERSION = "1.0.0"

#: Methods the client binds with typed request/result shapes.
TYPED_METHODS = (
    "rigorix.plan",
    "rigorix.validatePlan",
    "rigorix.run",
    "rigorix.execute",
    "rigorix.approve",
    "rigorix.checkEnforcement",
    "rigorix.audit.read",
    "rigorix.audit.list",
    "rigorix.audit.summary",
    "rigorix.template.list",
    "rigorix.template.get",
    "rigorix.template.create",
    "rigorix.template.validate",
    "rigorix.auth.login",
    "rigorix.auth.status",
    "rigorix.auth.logout",
    "rigorix.usageGuide",
    "rigorix.system.version",
)

#: Frozen methods owned by a server/enterprise surface (no typed wrapper).
SERVER_ONLY_METHODS = {
    "rigorix.audit.head": "enterprise ADR-016 Phase B ledger surface",
    "rigorix.audit.history": "enterprise ADR-016 Phase B ledger surface",
    "rigorix.audit.overdue": "enterprise ADR-016 Phase B ledger surface",
    "rigorix.audit.authorityFacts": (
        "authority-fact projection bundle export (audit evidence surface; "
        "no typed wrapper yet)"
    ),
    "rigorix.auth.verify": "enterprise-side JWKS claim verification",
    "rigorix.policy.bundle": "admin/enterprise control-plane export",
}

#: Every frozen method: typed first, then the server-only remainder.
METHODS = TYPED_METHODS + tuple(SERVER_ONLY_METHODS)


# ─── Shared shapes ──────────────────────────────────────────────────────────


class Constraints(TypedDict, total=False):
    max_tool_calls: Optional[int]
    max_tokens: Optional[int]
    max_duration_secs: Optional[int]
    blocked_tools: List[str]
    extensions: Dict[str, str]


class CostEstimateRequired(TypedDict):
    estimated_tokens: int
    estimated_tool_calls: int


class CostEstimate(CostEstimateRequired, total=False):
    estimated_cost_micro: Optional[int]


class StepResultRequired(TypedDict):
    step_name: str
    success: bool
    duration_ms: int


class StepResult(StepResultRequired, total=False):
    error: Optional[str]
    output: Any


# ─── Plan / validate / run / execute / approve ───────────────────────────────


class PlanParams(TypedDict):
    template_name: str


class PlanResultRequired(TypedDict):
    template_name: str
    description: str
    version: str
    tags: List[str]
    graph: Any
    enforcement: Any


class PlanResult(PlanResultRequired, total=False):
    constraints: Optional[Constraints]


class ValidatePlanParamsRequired(TypedDict):
    plan: Any


class ValidatePlanParams(ValidatePlanParamsRequired, total=False):
    identity: Any


class ValidateResultRequired(TypedDict):
    valid: bool
    warnings: List[str]
    errors: List[str]


class ValidateResult(ValidateResultRequired, total=False):
    estimated_cost: Optional[CostEstimate]


class RunParamsRequired(TypedDict):
    template_name: str


class RunParams(RunParamsRequired, total=False):
    execution_id: str
    repository: str
    author: str


class ExecuteParams(TypedDict, total=False):
    plan: Any
    template_name: str
    execution_id: str
    repository: str
    author: str


class ExecuteResultRequired(TypedDict):
    execution_id: str
    status: str
    steps: List[StepResult]
    duration_ms: int
    audit_uri: str


class ExecuteResult(ExecuteResultRequired, total=False):
    tokens_used: Optional[int]


class ApproveParamsRequired(TypedDict):
    execution_id: str
    step_names: List[str]


class ApproveParams(ApproveParamsRequired, total=False):
    approver_id: str
    authority: str
    token_claims_ref: str


class ApproveResultRequired(TypedDict):
    execution_id: str
    approved_steps: List[str]
    not_found: List[str]
    still_pending: List[str]
    resumed: bool
    message: str


class ApproveResult(ApproveResultRequired, total=False):
    final_state: Optional[str]


# ─── Enforcement ─────────────────────────────────────────────────────────────


class BudgetStatus(TypedDict):
    tool_calls_total: int
    tool_calls_remaining: int
    tokens_total: int
    tokens_remaining: int


class CircuitBreaker(TypedDict):
    name: str
    is_tripped: bool
    description: str


class CheckEnforcementResult(TypedDict):
    active: bool
    preset: str
    budget: BudgetStatus
    circuit_breakers: List[CircuitBreaker]


# ─── Audit ───────────────────────────────────────────────────────────────────


class AuditReadParamsRequired(TypedDict):
    execution_id: str


class AuditReadParams(AuditReadParamsRequired, total=False):
    format: str


class AuditReadResultRequired(TypedDict):
    execution_id: str
    status: str
    started_at: str
    completed_at: str
    duration_ms: int
    steps: List[StepResult]
    audit_uri: str


class AuditReadResult(AuditReadResultRequired, total=False):
    template_name: Optional[str]
    tokens_used: Optional[int]


class AuditListParams(TypedDict, total=False):
    status: str
    since: str
    until: str
    template: str
    limit: int


class AuditListItemRequired(TypedDict):
    execution_id: str
    status: str
    started_at: str
    duration_ms: int
    audit_uri: str


class AuditListItem(AuditListItemRequired, total=False):
    template_name: Optional[str]


class AuditListResult(TypedDict):
    total_count: int
    audits: List[AuditListItem]


class AuditSummaryParams(TypedDict, total=False):
    since: str
    until: str


class TopFailureRequired(TypedDict):
    description: str
    count: int


class TopFailure(TopFailureRequired, total=False):
    template_name: Optional[str]


class TopTemplate(TypedDict):
    name: str
    count: int
    avg_duration_ms: int


class AuditSummaryResultRequired(TypedDict):
    since: str
    until: str
    total_executions: int
    success_count: int
    failure_count: int
    success_rate: float
    total_duration_ms: int
    top_failures: List[TopFailure]
    top_templates: List[TopTemplate]


class AuditSummaryResult(AuditSummaryResultRequired, total=False):
    total_tokens: Optional[int]


# ─── Templates ───────────────────────────────────────────────────────────────


class TemplateListParams(TypedDict, total=False):
    limit: int
    search: str
    tags: List[str]


class TemplateListItem(TypedDict):
    name: str
    description: str
    version: str
    tags: List[str]
    step_count: int
    updated_at: str


class TemplateListResult(TypedDict):
    templates: List[TemplateListItem]


class TemplateGetParamsRequired(TypedDict):
    name: str


class TemplateGetParams(TemplateGetParamsRequired, total=False):
    format: str


class TemplateGetResultRequired(TypedDict):
    name: str
    description: str
    version: str
    tags: List[str]
    steps: List[Any]
    created_at: str
    updated_at: str


class TemplateGetResult(TemplateGetResultRequired, total=False):
    constraints: Optional[Constraints]
    metadata: Optional[Dict[str, str]]


class TemplateCreateParamsRequired(TypedDict):
    name: str
    plan: Any


class TemplateCreateParams(TemplateCreateParamsRequired, total=False):
    overwrite: bool


class TemplateCreateResult(TypedDict):
    name: str
    path: str
    status: str


class TemplateValidateParams(TypedDict):
    plan: Any


# ─── Auth ────────────────────────────────────────────────────────────────────


class AuthLoginParams(TypedDict, total=False):
    client_id: str
    issuer: str


class AuthLoginResult(TypedDict):
    status: str
    verification_uri: str
    user_code: str
    expires_in: int


class ClaimSummaryRequired(TypedDict):
    subject: str
    issuer: str


class ClaimSummary(ClaimSummaryRequired, total=False):
    authority: Optional[str]
    expires_at: Optional[str]


class AuthStatusResultRequired(TypedDict):
    status: str
    source: str


class AuthStatusResult(AuthStatusResultRequired, total=False):
    claim_summary: Optional[ClaimSummary]


class AuthLogoutResult(TypedDict):
    status: str


# ─── Self-description ────────────────────────────────────────────────────────


class UsageGuideResult(TypedDict):
    guide: str


class VersionResult(TypedDict):
    name: str
    engine_version: str
    api_version: str
    schemas: List[str]
    capabilities: List[str]
