// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package client

import "context"

// The typed surface mirrors `typescript-client/src/client.ts` method for method
// over the frozen `rigorix.*` catalog. `executeStep` is deliberately absent:
// it is not in the catalog and ADR-0001 D10 forbids a raw step-execution path.

// Plan calls `rigorix.plan`.
func (c *Client) Plan(ctx context.Context, params PlanParams) (PlanResult, error) {
	return CallTyped[PlanResult](ctx, c, "rigorix.plan", params)
}

// ValidatePlan calls `rigorix.validatePlan`.
func (c *Client) ValidatePlan(ctx context.Context, params ValidatePlanParams) (ValidateResult, error) {
	return CallTyped[ValidateResult](ctx, c, "rigorix.validatePlan", params)
}

// Run calls `rigorix.run`.
func (c *Client) Run(ctx context.Context, params RunParams) (ExecuteResult, error) {
	return CallTyped[ExecuteResult](ctx, c, "rigorix.run", params)
}

// Execute calls `rigorix.execute`.
func (c *Client) Execute(ctx context.Context, params ExecuteParams) (ExecuteResult, error) {
	return CallTyped[ExecuteResult](ctx, c, "rigorix.execute", params)
}

// Approve calls `rigorix.approve`.
func (c *Client) Approve(ctx context.Context, params ApproveParams) (ApproveResult, error) {
	return CallTyped[ApproveResult](ctx, c, "rigorix.approve", params)
}

// CheckEnforcement calls `rigorix.checkEnforcement`.
func (c *Client) CheckEnforcement(ctx context.Context) (CheckEnforcementResult, error) {
	return CallTyped[CheckEnforcementResult](ctx, c, "rigorix.checkEnforcement", EmptyParams{})
}

// AuditRead calls `rigorix.audit.read`.
func (c *Client) AuditRead(ctx context.Context, params AuditReadParams) (AuditReadResult, error) {
	return CallTyped[AuditReadResult](ctx, c, "rigorix.audit.read", params)
}

// AuditList calls `rigorix.audit.list`.
func (c *Client) AuditList(ctx context.Context, params AuditListParams) (AuditListResult, error) {
	return CallTyped[AuditListResult](ctx, c, "rigorix.audit.list", params)
}

// AuditSummary calls `rigorix.audit.summary`.
func (c *Client) AuditSummary(ctx context.Context, params AuditSummaryParams) (AuditSummaryResult, error) {
	return CallTyped[AuditSummaryResult](ctx, c, "rigorix.audit.summary", params)
}

// TemplateList calls `rigorix.template.list`.
func (c *Client) TemplateList(ctx context.Context, params TemplateListParams) (TemplateListResult, error) {
	return CallTyped[TemplateListResult](ctx, c, "rigorix.template.list", params)
}

// TemplateGet calls `rigorix.template.get`.
func (c *Client) TemplateGet(ctx context.Context, params TemplateGetParams) (TemplateGetResult, error) {
	return CallTyped[TemplateGetResult](ctx, c, "rigorix.template.get", params)
}

// TemplateCreate calls `rigorix.template.create`.
func (c *Client) TemplateCreate(ctx context.Context, params TemplateCreateParams) (TemplateCreateResult, error) {
	return CallTyped[TemplateCreateResult](ctx, c, "rigorix.template.create", params)
}

// TemplateValidate calls `rigorix.template.validate`.
func (c *Client) TemplateValidate(ctx context.Context, params TemplateValidateParams) (ValidateResult, error) {
	return CallTyped[ValidateResult](ctx, c, "rigorix.template.validate", params)
}

// AuthLogin calls `rigorix.auth.login`.
func (c *Client) AuthLogin(ctx context.Context, params AuthLoginParams) (AuthLoginResult, error) {
	return CallTyped[AuthLoginResult](ctx, c, "rigorix.auth.login", params)
}

// AuthStatus calls `rigorix.auth.status`.
func (c *Client) AuthStatus(ctx context.Context) (AuthStatusResult, error) {
	return CallTyped[AuthStatusResult](ctx, c, "rigorix.auth.status", EmptyParams{})
}

// AuthLogout calls `rigorix.auth.logout`.
func (c *Client) AuthLogout(ctx context.Context) (AuthLogoutResult, error) {
	return CallTyped[AuthLogoutResult](ctx, c, "rigorix.auth.logout", EmptyParams{})
}

// UsageGuide calls `rigorix.usageGuide`.
func (c *Client) UsageGuide(ctx context.Context) (UsageGuideResult, error) {
	return CallTyped[UsageGuideResult](ctx, c, "rigorix.usageGuide", EmptyParams{})
}
