/** Typed request/result interfaces mirroring `schemas/api/catalog.json` `$defs`
 * (ADR-0001). Field names match the frozen catalog exactly (snake_case). */

export interface EmptyParams {}

export interface PlanParams {
  template_name: string;
}

export interface PlanResult {
  template_name: string;
  description: string;
  version: string;
  tags: string[];
  graph: unknown;
  constraints?: Constraints | null;
  enforcement: unknown;
}

export interface Constraints {
  max_tool_calls?: number | null;
  max_tokens?: number | null;
  max_duration_secs?: number | null;
  blocked_tools?: string[];
  extensions?: Record<string, string>;
}

export interface ValidatePlanParams {
  plan: unknown;
  identity?: unknown;
}

export interface ValidateResult {
  valid: boolean;
  warnings: string[];
  errors: string[];
  estimated_cost?: CostEstimate | null;
}

export interface CostEstimate {
  estimated_tokens: number;
  estimated_tool_calls: number;
  estimated_cost_micro?: number | null;
}

export interface RunParams {
  template_name: string;
  execution_id?: string;
  repository?: string;
  author?: string;
}

export interface ExecuteParams {
  plan?: unknown;
  template_name?: string;
  execution_id?: string;
  repository?: string;
  author?: string;
}

export interface ExecuteResult {
  execution_id: string;
  status: string;
  steps: StepResult[];
  duration_ms: number;
  tokens_used?: number | null;
  audit_uri: string;
}

export interface StepResult {
  step_name: string;
  success: boolean;
  error?: string | null;
  output?: unknown;
  duration_ms: number;
}

export interface ApproveParams {
  execution_id: string;
  step_names: string[];
  approver_id?: string;
  authority?: string;
  token_claims_ref?: string;
}

export interface ApproveResult {
  execution_id: string;
  approved_steps: string[];
  not_found: string[];
  still_pending: string[];
  resumed: boolean;
  message: string;
  final_state?: string | null;
}

export interface CheckEnforcementResult {
  active: boolean;
  preset: string;
  budget: BudgetStatus;
  circuit_breakers: CircuitBreaker[];
}

export interface BudgetStatus {
  tool_calls_total: number;
  tool_calls_remaining: number;
  tokens_total: number;
  tokens_remaining: number;
}

export interface CircuitBreaker {
  name: string;
  is_tripped: boolean;
  description: string;
}

export interface AuditReadParams {
  execution_id: string;
  format?: string;
}

export interface AuditReadResult {
  execution_id: string;
  status: string;
  template_name?: string | null;
  started_at: string;
  completed_at: string;
  duration_ms: number;
  steps: StepResult[];
  tokens_used?: number | null;
  audit_uri: string;
}

export interface AuditListParams {
  status?: string;
  since?: string;
  until?: string;
  template?: string;
  limit?: number;
}

export interface AuditListResult {
  total_count: number;
  audits: AuditListItem[];
}

export interface AuditListItem {
  execution_id: string;
  status: string;
  template_name?: string | null;
  started_at: string;
  duration_ms: number;
  audit_uri: string;
}

export interface AuditSummaryParams {
  since?: string;
  until?: string;
}

export interface AuditSummaryResult {
  since: string;
  until: string;
  total_executions: number;
  success_count: number;
  failure_count: number;
  success_rate: number;
  total_duration_ms: number;
  total_tokens?: number | null;
  top_failures: TopFailure[];
  top_templates: TopTemplate[];
}

export interface TopFailure {
  description: string;
  count: number;
  template_name?: string | null;
}

export interface TopTemplate {
  name: string;
  count: number;
  avg_duration_ms: number;
}

export interface TemplateListParams {
  limit?: number;
  search?: string;
  tags?: string[];
}

export interface TemplateListResult {
  templates: TemplateListItem[];
}

export interface TemplateListItem {
  name: string;
  description: string;
  version: string;
  tags: string[];
  step_count: number;
  updated_at: string;
}

export interface TemplateGetParams {
  name: string;
  format?: string;
}

export interface TemplateGetResult {
  name: string;
  description: string;
  version: string;
  tags: string[];
  steps: unknown[];
  constraints?: Constraints | null;
  metadata?: Record<string, string> | null;
  created_at: string;
  updated_at: string;
}

export interface TemplateCreateParams {
  name: string;
  plan: unknown;
  overwrite?: boolean;
}

export interface TemplateCreateResult {
  name: string;
  path: string;
  status: string;
}

export interface TemplateValidateParams {
  plan: unknown;
}

export interface AuthLoginParams {
  client_id?: string;
  issuer?: string;
}

export interface AuthLoginResult {
  status: string;
  verification_uri: string;
  user_code: string;
  expires_in: number;
}

export interface AuthStatusResult {
  status: string;
  claim_summary?: ClaimSummary | null;
  source: string;
}

export interface ClaimSummary {
  subject: string;
  issuer: string;
  authority?: string | null;
  expires_at?: string | null;
}

export interface AuthLogoutResult {
  status: string;
}

export interface UsageGuideResult {
  guide: string;
}

export interface VersionResult {
  name: string;
  engine_version: string;
  api_version: string;
  schemas: string[];
  capabilities: string[];
}
