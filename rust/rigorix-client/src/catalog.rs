//! The frozen `rigorix.*` catalog as a client-side binding table (ADR-0001 D3).
//!
//! Every method in `schemas/api/catalog.json` is either **bound** by a typed
//! wrapper on [`crate::Client`] or **explicitly exempted** (server-only /
//! admin / enterprise). The catalog-drift test fails if a method is missing —
//! the namespace is closed, so no method is silently omitted. There is
//! deliberately **no** raw step-execution method (ADR-0001 D10).

/// How a catalog method is handled by this client.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Binding {
    /// A typed wrapper exists on [`crate::Client`].
    Typed,
    /// Deliberately not exposed — server-only / admin / enterprise (with a reason).
    ServerOnly(&'static str),
}

/// One catalog method and its client binding.
#[derive(Debug, Clone, Copy)]
pub struct MethodBinding {
    /// The frozen method name.
    pub name: &'static str,
    /// How the client treats it.
    pub binding: Binding,
}

/// The complete frozen catalog. Kept in sync with `schemas/api/catalog.json` by
/// the `catalog_drift` test.
pub const METHODS: &[MethodBinding] = &[
    MethodBinding {
        name: "rigorix.plan",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.validatePlan",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.run",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.execute",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.approve",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.checkEnforcement",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.audit.read",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.audit.list",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.audit.summary",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.audit.head",
        binding: Binding::ServerOnly("enterprise ADR-016 Phase B ledger surface"),
    },
    MethodBinding {
        name: "rigorix.audit.history",
        binding: Binding::ServerOnly("enterprise ADR-016 Phase B ledger surface"),
    },
    MethodBinding {
        name: "rigorix.audit.overdue",
        binding: Binding::ServerOnly("enterprise ADR-016 Phase B ledger surface"),
    },
    MethodBinding {
        name: "rigorix.template.list",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.template.get",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.template.create",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.template.validate",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.auth.login",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.auth.status",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.auth.logout",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.auth.verify",
        binding: Binding::ServerOnly("enterprise-side JWKS claim verification"),
    },
    MethodBinding {
        name: "rigorix.policy.bundle",
        binding: Binding::ServerOnly("admin/enterprise control-plane export"),
    },
    MethodBinding {
        name: "rigorix.usageGuide",
        binding: Binding::Typed,
    },
    MethodBinding {
        name: "rigorix.system.version",
        binding: Binding::Typed,
    },
];

/// Find a method's binding.
pub fn find(name: &str) -> Option<&'static MethodBinding> {
    METHODS.iter().find(|method| method.name == name)
}

/// Every bound method name.
pub fn names() -> Vec<&'static str> {
    METHODS.iter().map(|method| method.name).collect()
}

/// Ensure the client never exposes a raw step-execution method (ADR-0001 D10).
pub fn assert_no_raw_step_execution() -> Result<(), String> {
    for method in METHODS {
        let lower = method.name.to_ascii_lowercase();
        if lower.contains("step") && method.name != "rigorix.plan" {
            return Err(format!(
                "unexpected raw step-execution binding: {}",
                method.name
            ));
        }
        if method.name == "rigorix.executeStep" {
            return Err("raw step execution must never be bound".to_string());
        }
    }
    Ok(())
}
