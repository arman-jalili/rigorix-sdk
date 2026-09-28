// Package client is a protocol-only typed client for the frozen `rigorix.*`
// JSON-RPC catalog (ADR-0001). It binds every catalog method and exposes a
// transport seam; it never exposes a raw step-execution path (ADR-0001 D10).
package client

import "fmt"

// BindingKind classifies a catalog method.
type BindingKind string

const (
	// Typed identifies a method this client binds with typed request/result shapes.
	Typed BindingKind = "typed"
	// ServerOnly identifies a frozen method owned by a server/enterprise surface.
	ServerOnly BindingKind = "server_only"
)

// Binding records how (or whether) the client binds a method.
type Binding struct {
	Kind   BindingKind
	Reason string
}

// MethodBinding pairs a frozen method name with its binding.
type MethodBinding struct {
	Name    string
	Binding Binding
}

// Methods is the frozen catalog as a client-side binding table. The
// `catalog_drift` test fails if this diverges from `schemas/api/catalog.json`.
var Methods = []MethodBinding{
	{Name: "rigorix.plan", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.validatePlan", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.run", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.execute", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.approve", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.checkEnforcement", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.audit.read", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.audit.list", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.audit.summary", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.audit.head", Binding: Binding{Kind: ServerOnly, Reason: "enterprise ADR-016 Phase B ledger surface"}},
	{Name: "rigorix.audit.history", Binding: Binding{Kind: ServerOnly, Reason: "enterprise ADR-016 Phase B ledger surface"}},
	{Name: "rigorix.audit.overdue", Binding: Binding{Kind: ServerOnly, Reason: "enterprise ADR-016 Phase B ledger surface"}},
	{Name: "rigorix.template.list", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.template.get", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.template.create", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.template.validate", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.auth.login", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.auth.status", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.auth.logout", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.auth.verify", Binding: Binding{Kind: ServerOnly, Reason: "enterprise-side JWKS claim verification"}},
	{Name: "rigorix.policy.bundle", Binding: Binding{Kind: ServerOnly, Reason: "admin/enterprise control-plane export"}},
	{Name: "rigorix.usageGuide", Binding: Binding{Kind: Typed}},
	{Name: "rigorix.system.version", Binding: Binding{Kind: Typed}},
}

// MethodNames returns every bound catalog method name.
func MethodNames() []string {
	out := make([]string, len(Methods))
	for i, method := range Methods {
		out[i] = method.Name
	}
	return out
}

// Find returns the binding for a method name.
func Find(name string) (MethodBinding, bool) {
	for _, method := range Methods {
		if method.Name == name {
			return method, true
		}
	}
	return MethodBinding{}, false
}

// AssertNoRawStepExecution fails if a raw step-execution binding appears
// (ADR-0001 D10: governed flows only).
func AssertNoRawStepExecution() error {
	for _, method := range Methods {
		if method.Name == "rigorix.executeStep" {
			return fmt.Errorf("raw step execution must never be bound: %s", method.Name)
		}
	}
	return nil
}
