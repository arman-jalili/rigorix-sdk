//! Transport seam — the crate is HTTP-framework-free.
//!
//! Implement [`Transport`] for your HTTP client (e.g. `reqwest`) and hand it to
//! [`crate::Client`]. The request body is JSON-RPC 2.0; return the response body
//! verbatim (a JSON object or, for batches, a JSON array).

use std::collections::VecDeque;
use std::sync::Mutex;

/// POST a JSON-RPC body and return the raw response body.
pub trait Transport: Send + Sync {
    /// Send `body` (JSON) and return the response body (JSON).
    fn post(&self, body: &str) -> Result<String, String>;
}

/// A test transport that records requests and replays queued responses.
pub struct MockTransport {
    responses: Mutex<VecDeque<Result<String, String>>>,
    requests: Mutex<Vec<String>>,
}

impl MockTransport {
    /// Build from a queue of response bodies (or errors).
    pub fn new(responses: Vec<Result<String, String>>) -> Self {
        Self {
            responses: Mutex::new(responses.into()),
            requests: Mutex::new(Vec::new()),
        }
    }

    /// Build from successful response bodies.
    pub fn ok(responses: Vec<String>) -> Self {
        Self::new(responses.into_iter().map(Ok).collect())
    }

    /// Queue another response.
    pub fn push(&self, response: impl Into<String>) {
        self.responses
            .lock()
            .expect("mock lock")
            .push_back(Ok(response.into()));
    }

    /// Every request body sent through this transport, in order.
    pub fn requests(&self) -> Vec<String> {
        self.requests.lock().expect("mock lock").clone()
    }
}

impl Transport for MockTransport {
    fn post(&self, body: &str) -> Result<String, String> {
        self.requests
            .lock()
            .expect("mock lock")
            .push(body.to_string());
        self.responses
            .lock()
            .expect("mock lock")
            .pop_front()
            .unwrap_or_else(|| Err("mock transport: no queued response".to_string()))
    }
}
