//! Error taxonomy mapping (`schemas/api/errors.json`, ADR-0001 D6).
//!
//! `data.type` is the stable machine identifier. Every declared type maps to a
//! distinct [`ApiError`] variant; an unknown type falls through to
//! [`ApiError::Unknown`] — never a panic.

use serde::Deserialize;
use serde_json::Value;

/// The JSON-RPC `error` object.
#[derive(Debug, Clone, Deserialize)]
pub struct RpcError {
    pub code: i64,
    pub message: String,
    #[serde(default)]
    pub data: Option<Value>,
}

impl RpcError {
    /// The stable `data.type` string, when present.
    pub fn error_type(&self) -> Option<&str> {
        self.data
            .as_ref()
            .and_then(|data| data.get("type"))
            .and_then(Value::as_str)
    }

    /// Map this error onto the typed [`ApiError`] taxonomy.
    pub fn api_error(&self) -> ApiError {
        match self.error_type() {
            Some(name) => ApiError::from_type(name),
            None => ApiError::Unknown(self.message.clone()),
        }
    }

    /// The `data.rule_id` (for `denied_by_sequence`), when present.
    pub fn rule_id(&self) -> Option<&str> {
        self.data
            .as_ref()
            .and_then(|data| data.get("rule_id"))
            .and_then(Value::as_str)
    }

    /// The `data.step` (for `denied_by_sequence`), when present.
    pub fn step(&self) -> Option<&str> {
        self.data
            .as_ref()
            .and_then(|data| data.get("step"))
            .and_then(Value::as_str)
    }
}

/// The typed error taxonomy (`errors.json` `$defs.errorType`).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum ApiError {
    ParseError,
    InvalidRequest,
    MethodNotFound,
    InvalidParams,
    InternalError,
    NotAuthenticated,
    InsufficientScope,
    DeniedBySequence,
    PolicyViolation,
    ApprovalRequired,
    IdentityRequired,
    BudgetExhausted,
    Timeout,
    ApiErrorResponse,
    NotEnabled,
    /// An unrecognized `data.type` — never a panic.
    Unknown(String),
}

impl ApiError {
    /// Map a `data.type` string to its variant.
    pub fn from_type(error_type: &str) -> Self {
        match error_type {
            "parse_error" => Self::ParseError,
            "invalid_request" => Self::InvalidRequest,
            "method_not_found" => Self::MethodNotFound,
            "invalid_params" => Self::InvalidParams,
            "internal_error" => Self::InternalError,
            "not_authenticated" => Self::NotAuthenticated,
            "insufficient_scope" => Self::InsufficientScope,
            "denied_by_sequence" => Self::DeniedBySequence,
            "policy_violation" => Self::PolicyViolation,
            "approval_required" => Self::ApprovalRequired,
            "identity_required" => Self::IdentityRequired,
            "budget_exhausted" => Self::BudgetExhausted,
            "timeout" => Self::Timeout,
            "api_error" => Self::ApiErrorResponse,
            "not_enabled" => Self::NotEnabled,
            other => Self::Unknown(other.to_string()),
        }
    }

    /// The `data.type` string for this variant.
    pub fn as_type(&self) -> &str {
        match self {
            Self::ParseError => "parse_error",
            Self::InvalidRequest => "invalid_request",
            Self::MethodNotFound => "method_not_found",
            Self::InvalidParams => "invalid_params",
            Self::InternalError => "internal_error",
            Self::NotAuthenticated => "not_authenticated",
            Self::InsufficientScope => "insufficient_scope",
            Self::DeniedBySequence => "denied_by_sequence",
            Self::PolicyViolation => "policy_violation",
            Self::ApprovalRequired => "approval_required",
            Self::IdentityRequired => "identity_required",
            Self::BudgetExhausted => "budget_exhausted",
            Self::Timeout => "timeout",
            Self::ApiErrorResponse => "api_error",
            Self::NotEnabled => "not_enabled",
            Self::Unknown(name) => name,
        }
    }
}

/// Every client-side failure.
#[derive(Debug, thiserror::Error)]
pub enum ClientError {
    /// The transport failed (network/IO) or returned a non-2xx status.
    #[error("transport error: {0}")]
    Transport(String),
    /// The request/response body was not valid JSON.
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    /// A JSON-RPC `error` object, mapped to the typed taxonomy.
    #[error("json-rpc error {code}: {message} ({error_type:?})")]
    Rpc {
        code: i64,
        message: String,
        error_type: ApiError,
    },
    /// A malformed JSON-RPC response (no `result` and no `error`).
    #[error("protocol error: {0}")]
    Protocol(String),
    /// The server's `apiVersion` is incompatible with this client's constraint.
    #[error("server apiVersion {server} is incompatible with the client constraint (major {client_major})")]
    VersionMismatch { server: String, client_major: u64 },
}

impl From<RpcError> for ClientError {
    fn from(error: RpcError) -> Self {
        Self::Rpc {
            code: error.code,
            message: error.message.clone(),
            error_type: error.api_error(),
        }
    }
}
