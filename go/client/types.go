// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package client

// DTOs mirror `schemas/api/catalog.json` `$defs`; `typescript-client/src/types.ts`
// is the field-for-field reference. Nullable fields are pointers so an absent
// value and an explicit `null` remain distinguishable.

// EmptyParams is the `{}` params object for no-argument methods.
type EmptyParams struct{}

// PlanParams is `rigorix.plan` params.
type PlanParams struct {
	TemplateName string `json:"template_name"`
}

// PlanResult is `rigorix.plan` result.
type PlanResult struct {
	TemplateName string       `json:"template_name"`
	Description  string       `json:"description"`
	Version      string       `json:"version"`
	Tags         []string     `json:"tags"`
	Graph        any          `json:"graph"`
	Constraints  *Constraints `json:"constraints,omitempty"`
	Enforcement  any          `json:"enforcement"`
}

// Constraints is the plan's execution budget.
type Constraints struct {
	MaxToolCalls    *int              `json:"max_tool_calls,omitempty"`
	MaxTokens       *int              `json:"max_tokens,omitempty"`
	MaxDurationSecs *int              `json:"max_duration_secs,omitempty"`
	BlockedTools    []string          `json:"blocked_tools,omitempty"`
	Extensions      map[string]string `json:"extensions,omitempty"`
}

// ValidatePlanParams is `rigorix.validatePlan` params.
type ValidatePlanParams struct {
	Plan     any `json:"plan"`
	Identity any `json:"identity,omitempty"`
}

// ValidateResult is `rigorix.validatePlan` / `rigorix.template.validate` result.
type ValidateResult struct {
	Valid         bool          `json:"valid"`
	Warnings      []string      `json:"warnings"`
	Errors        []string      `json:"errors"`
	EstimatedCost *CostEstimate `json:"estimated_cost,omitempty"`
}

// CostEstimate is the plan's estimated cost.
type CostEstimate struct {
	EstimatedTokens    int    `json:"estimated_tokens"`
	EstimatedToolCalls int    `json:"estimated_tool_calls"`
	EstimatedCostMicro *int64 `json:"estimated_cost_micro,omitempty"`
}

// RunParams is `rigorix.run` params.
type RunParams struct {
	TemplateName string `json:"template_name"`
	ExecutionID  string `json:"execution_id,omitempty"`
	Repository   string `json:"repository,omitempty"`
	Author       string `json:"author,omitempty"`
}

// ExecuteParams is `rigorix.execute` params.
type ExecuteParams struct {
	Plan         any    `json:"plan,omitempty"`
	TemplateName string `json:"template_name,omitempty"`
	ExecutionID  string `json:"execution_id,omitempty"`
	Repository   string `json:"repository,omitempty"`
	Author       string `json:"author,omitempty"`
}

// ExecuteResult is `rigorix.run` / `rigorix.execute` result.
type ExecuteResult struct {
	ExecutionID string       `json:"execution_id"`
	Status      string       `json:"status"`
	Steps       []StepResult `json:"steps"`
	DurationMS  int64        `json:"duration_ms"`
	TokensUsed  *int64       `json:"tokens_used,omitempty"`
	AuditURI    string       `json:"audit_uri"`
}

// StepResult is one executed step.
type StepResult struct {
	StepName   string  `json:"step_name"`
	Success    bool    `json:"success"`
	Error      *string `json:"error,omitempty"`
	Output     any     `json:"output,omitempty"`
	DurationMS int64   `json:"duration_ms"`
}

// ApproveParams is `rigorix.approve` params.
type ApproveParams struct {
	ExecutionID    string   `json:"execution_id"`
	StepNames      []string `json:"step_names"`
	ApproverID     string   `json:"approver_id,omitempty"`
	Authority      string   `json:"authority,omitempty"`
	TokenClaimsRef string   `json:"token_claims_ref,omitempty"`
}

// ApproveResult is `rigorix.approve` result.
type ApproveResult struct {
	ExecutionID   string   `json:"execution_id"`
	ApprovedSteps []string `json:"approved_steps"`
	NotFound      []string `json:"not_found"`
	StillPending  []string `json:"still_pending"`
	Resumed       bool     `json:"resumed"`
	Message       string   `json:"message"`
	FinalState    *string  `json:"final_state,omitempty"`
}

// CheckEnforcementResult is `rigorix.checkEnforcement` result.
type CheckEnforcementResult struct {
	Active          bool             `json:"active"`
	Preset          string           `json:"preset"`
	Budget          BudgetStatus     `json:"budget"`
	CircuitBreakers []CircuitBreaker `json:"circuit_breakers"`
}

// BudgetStatus is the current enforcement budget.
type BudgetStatus struct {
	ToolCallsTotal     int `json:"tool_calls_total"`
	ToolCallsRemaining int `json:"tool_calls_remaining"`
	TokensTotal        int `json:"tokens_total"`
	TokensRemaining    int `json:"tokens_remaining"`
}

// CircuitBreaker is one enforcement circuit breaker.
type CircuitBreaker struct {
	Name        string `json:"name"`
	IsTripped   bool   `json:"is_tripped"`
	Description string `json:"description"`
}

// AuditReadParams is `rigorix.audit.read` params.
type AuditReadParams struct {
	ExecutionID string `json:"execution_id"`
	Format      string `json:"format,omitempty"`
}

// AuditReadResult is `rigorix.audit.read` result.
type AuditReadResult struct {
	ExecutionID  string       `json:"execution_id"`
	Status       string       `json:"status"`
	TemplateName *string      `json:"template_name,omitempty"`
	StartedAt    string       `json:"started_at"`
	CompletedAt  string       `json:"completed_at"`
	DurationMS   int64        `json:"duration_ms"`
	Steps        []StepResult `json:"steps"`
	TokensUsed   *int64       `json:"tokens_used,omitempty"`
	AuditURI     string       `json:"audit_uri"`
}

// AuditListParams is `rigorix.audit.list` params.
type AuditListParams struct {
	Status   string `json:"status,omitempty"`
	Since    string `json:"since,omitempty"`
	Until    string `json:"until,omitempty"`
	Template string `json:"template,omitempty"`
	Limit    *int   `json:"limit,omitempty"`
}

// AuditListResult is `rigorix.audit.list` result.
type AuditListResult struct {
	TotalCount int             `json:"total_count"`
	Audits     []AuditListItem `json:"audits"`
}

// AuditListItem is one audit summary row.
type AuditListItem struct {
	ExecutionID  string  `json:"execution_id"`
	Status       string  `json:"status"`
	TemplateName *string `json:"template_name,omitempty"`
	StartedAt    string  `json:"started_at"`
	DurationMS   int64   `json:"duration_ms"`
	AuditURI     string  `json:"audit_uri"`
}

// AuditSummaryParams is `rigorix.audit.summary` params.
type AuditSummaryParams struct {
	Since string `json:"since,omitempty"`
	Until string `json:"until,omitempty"`
}

// AuditSummaryResult is `rigorix.audit.summary` result.
type AuditSummaryResult struct {
	Since           string        `json:"since"`
	Until           string        `json:"until"`
	TotalExecutions int           `json:"total_executions"`
	SuccessCount    int           `json:"success_count"`
	FailureCount    int           `json:"failure_count"`
	SuccessRate     float64       `json:"success_rate"`
	TotalDurationMS int64         `json:"total_duration_ms"`
	TotalTokens     *int64        `json:"total_tokens,omitempty"`
	TopFailures     []TopFailure  `json:"top_failures"`
	TopTemplates    []TopTemplate `json:"top_templates"`
}

// TopFailure is one aggregated failure in the audit summary.
type TopFailure struct {
	Description  string  `json:"description"`
	Count        int     `json:"count"`
	TemplateName *string `json:"template_name,omitempty"`
}

// TopTemplate is one aggregated template in the audit summary.
type TopTemplate struct {
	Name          string `json:"name"`
	Count         int    `json:"count"`
	AvgDurationMS int64  `json:"avg_duration_ms"`
}

// TemplateListParams is `rigorix.template.list` params.
type TemplateListParams struct {
	Limit  *int     `json:"limit,omitempty"`
	Search string   `json:"search,omitempty"`
	Tags   []string `json:"tags,omitempty"`
}

// TemplateListResult is `rigorix.template.list` result.
type TemplateListResult struct {
	Templates []TemplateListItem `json:"templates"`
}

// TemplateListItem is one template summary.
type TemplateListItem struct {
	Name        string   `json:"name"`
	Description string   `json:"description"`
	Version     string   `json:"version"`
	Tags        []string `json:"tags"`
	StepCount   int      `json:"step_count"`
	UpdatedAt   string   `json:"updated_at"`
}

// TemplateGetParams is `rigorix.template.get` params.
type TemplateGetParams struct {
	Name   string `json:"name"`
	Format string `json:"format,omitempty"`
}

// TemplateGetResult is `rigorix.template.get` result.
type TemplateGetResult struct {
	Name        string            `json:"name"`
	Description string            `json:"description"`
	Version     string            `json:"version"`
	Tags        []string          `json:"tags"`
	Steps       []any             `json:"steps"`
	Constraints *Constraints      `json:"constraints,omitempty"`
	Metadata    map[string]string `json:"metadata,omitempty"`
	CreatedAt   string            `json:"created_at"`
	UpdatedAt   string            `json:"updated_at"`
}

// TemplateCreateParams is `rigorix.template.create` params.
type TemplateCreateParams struct {
	Name      string `json:"name"`
	Plan      any    `json:"plan"`
	Overwrite *bool  `json:"overwrite,omitempty"`
}

// TemplateCreateResult is `rigorix.template.create` result.
type TemplateCreateResult struct {
	Name   string `json:"name"`
	Path   string `json:"path"`
	Status string `json:"status"`
}

// TemplateValidateParams is `rigorix.template.validate` params.
type TemplateValidateParams struct {
	Plan any `json:"plan"`
}

// AuthLoginParams is `rigorix.auth.login` params.
type AuthLoginParams struct {
	ClientID string `json:"client_id,omitempty"`
	Issuer   string `json:"issuer,omitempty"`
}

// AuthLoginResult is `rigorix.auth.login` result.
type AuthLoginResult struct {
	Status          string `json:"status"`
	VerificationURI string `json:"verification_uri"`
	UserCode        string `json:"user_code"`
	ExpiresIn       int    `json:"expires_in"`
}

// AuthStatusResult is `rigorix.auth.status` result.
type AuthStatusResult struct {
	Status       string        `json:"status"`
	ClaimSummary *ClaimSummary `json:"claim_summary,omitempty"`
	Source       string        `json:"source"`
}

// ClaimSummary is the verified claim projection.
type ClaimSummary struct {
	Subject   string  `json:"subject"`
	Issuer    string  `json:"issuer"`
	Authority *string `json:"authority,omitempty"`
	ExpiresAt *string `json:"expires_at,omitempty"`
}

// AuthLogoutResult is `rigorix.auth.logout` result.
type AuthLogoutResult struct {
	Status string `json:"status"`
}

// UsageGuideResult is `rigorix.usageGuide` result.
type UsageGuideResult struct {
	Guide string `json:"guide"`
}

// VersionResult mirrors `rigorix.system.version`.
type VersionResult struct {
	Name          string   `json:"name"`
	EngineVersion string   `json:"engine_version"`
	APIVersion    string   `json:"api_version"`
	Schemas       []string `json:"schemas"`
	Capabilities  []string `json:"capabilities"`
}
