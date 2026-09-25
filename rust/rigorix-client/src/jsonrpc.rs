//! JSON-RPC 2.0 framing (ADR-0001 D1): single requests, batch arrays, and
//! notifications (requests with no `id`).

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::error::RpcError;

/// A JSON-RPC request id — number or string, per the spec.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum RequestId {
    Number(i64),
    String(String),
}

impl From<i64> for RequestId {
    fn from(value: i64) -> Self {
        Self::Number(value)
    }
}

/// One JSON-RPC 2.0 request. A request without `id` is a notification.
#[derive(Debug, Clone, Serialize)]
pub struct Request {
    pub jsonrpc: &'static str,
    pub method: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub params: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<RequestId>,
}

impl Request {
    /// A request expecting a response (`id` set).
    pub fn call(
        id: impl Into<RequestId>,
        method: impl Into<String>,
        params: Option<Value>,
    ) -> Self {
        Self {
            jsonrpc: "2.0",
            method: method.into(),
            params,
            id: Some(id.into()),
        }
    }

    /// A notification — no `id`, no response expected.
    pub fn notification(method: impl Into<String>, params: Option<Value>) -> Self {
        Self {
            jsonrpc: "2.0",
            method: method.into(),
            params,
            id: None,
        }
    }

    /// Whether this request expects a response.
    pub fn is_notification(&self) -> bool {
        self.id.is_none()
    }
}

/// One JSON-RPC 2.0 response (the `result`/`error` union, `id` echoed).
#[derive(Debug, Clone, Deserialize)]
pub struct Response {
    #[serde(default)]
    pub jsonrpc: String,
    #[serde(default)]
    pub id: Option<RequestId>,
    #[serde(default)]
    pub result: Option<Value>,
    #[serde(default)]
    pub error: Option<RpcError>,
}

impl Response {
    /// Whether this response carries an error.
    pub fn is_error(&self) -> bool {
        self.error.is_some()
    }
}

/// Serialize a single request to its JSON body.
pub fn encode(request: &Request) -> Result<String, serde_json::Error> {
    serde_json::to_string(request)
}

/// Serialize a batch (JSON array) to its JSON body.
pub fn encode_batch(requests: &[Request]) -> Result<String, serde_json::Error> {
    serde_json::to_string(requests)
}

/// Parse a single response body.
pub fn decode(body: &str) -> Result<Response, serde_json::Error> {
    serde_json::from_str(body)
}

/// Parse a batch response body.
pub fn decode_batch(body: &str) -> Result<Vec<Response>, serde_json::Error> {
    serde_json::from_str(body)
}
