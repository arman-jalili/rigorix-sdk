/** The frozen `rigorix.*` catalog as a client-side binding table (ADR-0001 D3).
 *
 * Every method in `schemas/api/catalog.json` is either **typed** or
 * **explicitly server-only**. The `catalog_drift` test fails if the two
 * diverge — the namespace is closed, so no method is silently omitted. There is
 * deliberately no raw step-execution method (ADR-0001 D10). */

export type Binding = { kind: "typed" } | { kind: "server_only"; reason: string };

export interface MethodBinding {
  name: string;
  binding: Binding;
}

export const METHODS: MethodBinding[] = [
  { name: "rigorix.plan", binding: { kind: "typed" } },
  { name: "rigorix.validatePlan", binding: { kind: "typed" } },
  { name: "rigorix.run", binding: { kind: "typed" } },
  { name: "rigorix.execute", binding: { kind: "typed" } },
  { name: "rigorix.approve", binding: { kind: "typed" } },
  { name: "rigorix.checkEnforcement", binding: { kind: "typed" } },
  { name: "rigorix.audit.read", binding: { kind: "typed" } },
  { name: "rigorix.audit.list", binding: { kind: "typed" } },
  { name: "rigorix.audit.summary", binding: { kind: "typed" } },
  {
    name: "rigorix.audit.head",
    binding: { kind: "server_only", reason: "enterprise ADR-016 Phase B ledger surface" },
  },
  {
    name: "rigorix.audit.history",
    binding: { kind: "server_only", reason: "enterprise ADR-016 Phase B ledger surface" },
  },
  {
    name: "rigorix.audit.overdue",
    binding: { kind: "server_only", reason: "enterprise ADR-016 Phase B ledger surface" },
  },
  {
    name: "rigorix.audit.authorityFacts",
    binding: {
      kind: "server_only",
      reason: "authority-fact projection bundle export (audit evidence surface; no typed wrapper yet)",
    },
  },
  { name: "rigorix.template.list", binding: { kind: "typed" } },
  { name: "rigorix.template.get", binding: { kind: "typed" } },
  { name: "rigorix.template.create", binding: { kind: "typed" } },
  { name: "rigorix.template.validate", binding: { kind: "typed" } },
  { name: "rigorix.auth.login", binding: { kind: "typed" } },
  { name: "rigorix.auth.status", binding: { kind: "typed" } },
  { name: "rigorix.auth.logout", binding: { kind: "typed" } },
  {
    name: "rigorix.auth.verify",
    binding: { kind: "server_only", reason: "enterprise-side JWKS claim verification" },
  },
  {
    name: "rigorix.policy.bundle",
    binding: { kind: "server_only", reason: "admin/enterprise control-plane export" },
  },
  { name: "rigorix.usageGuide", binding: { kind: "typed" } },
  { name: "rigorix.system.version", binding: { kind: "typed" } },
];

export function find(name: string): MethodBinding | undefined {
  return METHODS.find((method) => method.name === name);
}

export function names(): string[] {
  return METHODS.map((method) => method.name);
}

/** Ensure the client never exposes a raw step-execution method (ADR-0001 D10). */
export function assertNoRawStepExecution(): void {
  for (const method of METHODS) {
    const lower = method.name.toLowerCase();
    if (lower.includes("step") && method.name !== "rigorix.plan") {
      throw new Error(`unexpected raw step-execution binding: ${method.name}`);
    }
    if (method.name === "rigorix.executeStep") {
      throw new Error("raw step execution must never be bound");
    }
  }
}
