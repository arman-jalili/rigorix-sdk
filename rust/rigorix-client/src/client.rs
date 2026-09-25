//! The typed client over a [`Transport`] (ADR-0001 D1/D3).

use std::sync::atomic::{AtomicI64, Ordering};

use serde::{de::DeserializeOwned, Serialize};
use serde_json::Value;

use crate::error::ClientError;
use crate::jsonrpc::{self, Request, RequestId, Response};
use crate::transport::Transport;
use crate::types::*;

/// One raw call in a batch.
#[derive(Debug, Clone)]
pub struct BatchCall {
    /// The frozen method name.
    pub method: String,
    /// The request params.
    pub params: Value,
}

impl BatchCall {
    /// Build a batch call.
    pub fn new(method: impl Into<String>, params: Value) -> Self {
        Self {
            method: method.into(),
            params,
        }
    }
}

/// A typed JSON-RPC client over the frozen `rigorix.*` catalog.
pub struct Client<T: Transport> {
    transport: T,
    next_id: AtomicI64,
}

impl<T: Transport> Client<T> {
    /// Build a client over `transport`.
    pub fn new(transport: T) -> Self {
        Self {
            transport,
            next_id: AtomicI64::new(1),
        }
    }

    /// The underlying transport.
    pub fn transport(&self) -> &T {
        &self.transport
    }

    fn next_id(&self) -> RequestId {
        RequestId::Number(self.next_id.fetch_add(1, Ordering::SeqCst))
    }

    /// Call a method and return the raw `result` value.
    pub fn call_raw(&self, method: &str, params: Value) -> Result<Value, ClientError> {
        let request = Request::call(self.next_id(), method, Some(params));
        let body = jsonrpc::encode(&request)?;
        let response_body = self.transport.post(&body).map_err(ClientError::Transport)?;
        into_result(jsonrpc::decode(&response_body)?)
    }

    /// Call a method with typed params, deserializing a typed result.
    pub fn call<P: Serialize, R: DeserializeOwned>(
        &self,
        method: &str,
        params: &P,
    ) -> Result<R, ClientError> {
        let value = self.call_raw(method, serde_json::to_value(params)?)?;
        Ok(serde_json::from_value(value)?)
    }

    /// Send a notification (no `id`; no response expected).
    pub fn notify<P: Serialize>(&self, method: &str, params: &P) -> Result<(), ClientError> {
        let request = Request::notification(method, Some(serde_json::to_value(params)?));
        let body = jsonrpc::encode(&request)?;
        self.transport
            .post(&body)
            .map(|_| ())
            .map_err(ClientError::Transport)
    }

    /// Send a batch (one JSON array) and return the raw responses.
    pub fn batch_raw(&self, calls: &[BatchCall]) -> Result<Vec<Response>, ClientError> {
        let requests: Vec<Request> = calls
            .iter()
            .map(|call| {
                Request::call(
                    self.next_id(),
                    call.method.clone(),
                    Some(call.params.clone()),
                )
            })
            .collect();
        let body = jsonrpc::encode_batch(&requests)?;
        let response_body = self.transport.post(&body).map_err(ClientError::Transport)?;
        Ok(jsonrpc::decode_batch(&response_body)?)
    }

    // ─── Governed flows ──────────────────────────────────────────────────

    /// `rigorix.plan` — resolve a template to a planned DAG.
    pub fn plan(&self, params: &PlanParams) -> Result<PlanResult, ClientError> {
        self.call("rigorix.plan", params)
    }

    /// `rigorix.validatePlan` — validate without executing.
    pub fn validate_plan(
        &self,
        params: &ValidatePlanParams,
    ) -> Result<ValidateResult, ClientError> {
        self.call("rigorix.validatePlan", params)
    }

    /// `rigorix.run` — governed execution of a template's plan.
    pub fn run(&self, params: &RunParams) -> Result<ExecuteResult, ClientError> {
        self.call("rigorix.run", params)
    }

    /// `rigorix.execute` — governed execution of an explicit plan/template.
    pub fn execute(&self, params: &ExecuteParams) -> Result<ExecuteResult, ClientError> {
        self.call("rigorix.execute", params)
    }

    /// `rigorix.approve` — approve steps bound to the attested session.
    pub fn approve(&self, params: &ApproveParams) -> Result<ApproveResult, ClientError> {
        self.call("rigorix.approve", params)
    }

    /// `rigorix.checkEnforcement` — enforcement state snapshot.
    pub fn check_enforcement(&self) -> Result<CheckEnforcementResult, ClientError> {
        self.call("rigorix.checkEnforcement", &EmptyParams {})
    }

    // ─── Audit (read side) ───────────────────────────────────────────────

    /// `rigorix.audit.read`.
    pub fn audit_read(&self, params: &AuditReadParams) -> Result<AuditReadResult, ClientError> {
        self.call("rigorix.audit.read", params)
    }

    /// `rigorix.audit.list`.
    pub fn audit_list(&self, params: &AuditListParams) -> Result<AuditListResult, ClientError> {
        self.call("rigorix.audit.list", params)
    }

    /// `rigorix.audit.summary`.
    pub fn audit_summary(
        &self,
        params: &AuditSummaryParams,
    ) -> Result<AuditSummaryResult, ClientError> {
        self.call("rigorix.audit.summary", params)
    }

    // ─── Templates ───────────────────────────────────────────────────────

    /// `rigorix.template.list`.
    pub fn template_list(
        &self,
        params: &TemplateListParams,
    ) -> Result<TemplateListResult, ClientError> {
        self.call("rigorix.template.list", params)
    }

    /// `rigorix.template.get`.
    pub fn template_get(
        &self,
        params: &TemplateGetParams,
    ) -> Result<TemplateGetResult, ClientError> {
        self.call("rigorix.template.get", params)
    }

    /// `rigorix.template.create`.
    pub fn template_create(
        &self,
        params: &TemplateCreateParams,
    ) -> Result<TemplateCreateResult, ClientError> {
        self.call("rigorix.template.create", params)
    }

    /// `rigorix.template.validate`.
    pub fn template_validate(
        &self,
        params: &TemplateValidateParams,
    ) -> Result<ValidateResult, ClientError> {
        self.call("rigorix.template.validate", params)
    }

    // ─── Auth (device flow) ──────────────────────────────────────────────

    /// `rigorix.auth.login` — begin the OIDC device flow.
    pub fn auth_login(&self, params: &AuthLoginParams) -> Result<AuthLoginResult, ClientError> {
        self.call("rigorix.auth.login", params)
    }

    /// `rigorix.auth.status` — redacted session status.
    pub fn auth_status(&self) -> Result<AuthStatusResult, ClientError> {
        self.call("rigorix.auth.status", &EmptyParams {})
    }

    /// `rigorix.auth.logout`.
    pub fn auth_logout(&self) -> Result<AuthLogoutResult, ClientError> {
        self.call("rigorix.auth.logout", &EmptyParams {})
    }

    // ─── Self-description / negotiation ──────────────────────────────────

    /// `rigorix.usageGuide`.
    pub fn usage_guide(&self) -> Result<UsageGuideResult, ClientError> {
        self.call("rigorix.usageGuide", &EmptyParams {})
    }

    /// `rigorix.system.version`, including the client's API constraint check.
    pub fn version(&self) -> Result<VersionResult, ClientError> {
        let version: VersionResult = self.call("rigorix.system.version", &EmptyParams {})?;
        self.check_version(&version)?;
        Ok(version)
    }

    /// Verify the server's `api_version` is compatible with this client's major.
    pub fn check_version(&self, version: &VersionResult) -> Result<(), ClientError> {
        let server_major = version
            .api_version
            .split('.')
            .next()
            .and_then(|major| major.parse::<u64>().ok())
            .unwrap_or_default();
        if server_major != crate::CLIENT_API_MAJOR {
            return Err(ClientError::VersionMismatch {
                server: version.api_version.clone(),
                client_major: crate::CLIENT_API_MAJOR,
            });
        }
        Ok(())
    }
}

fn into_result(response: Response) -> Result<Value, ClientError> {
    if let Some(error) = response.error {
        return Err(ClientError::from(error));
    }
    response.result.ok_or_else(|| {
        ClientError::Protocol("response has neither `result` nor `error`".to_string())
    })
}
