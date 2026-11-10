// SPDX-License-Identifier: Apache-2.0
//! rigorix-client — protocol-only typed client for the frozen `rigorix.*`
//! JSON-RPC catalog.
//!
//! @canonical schemas/api/catalog.json — the frozen method/type catalog
//! (ADR-0001). This crate mirrors its `$defs` and exposes **governed flows
//! only**: there is no raw step-execution surface (ADR-0001 D10), and no
//! `rigorix-engine` dependency (D-1) — execution logic never moves into an SDK.
//!
//! Transport is JSON-RPC 2.0 over `POST /rpc` (ADR-0001 D1): single requests,
//! batch arrays, and notifications (no `id`). The [`Transport`] trait keeps the
//! crate HTTP-framework-free; supply your own (e.g. `reqwest`) or the test
//! [`transport::MockTransport`]. Errors map the `errors.json` taxonomy into
//! [`error::ApiError`].

pub mod auth;
pub mod catalog;
pub mod client;
pub mod error;
pub mod jsonrpc;
pub mod transport;
pub mod types;

pub use client::Client;
pub use error::{ApiError, ClientError, RpcError};
pub use jsonrpc::{Request, RequestId, Response};
pub use transport::Transport;

/// The native API major this client targets (catalog.json `apiVersion`).
pub const CLIENT_API_MAJOR: u64 = 1;

/// The full native API version this client was built against.
pub const CLIENT_API_VERSION: &str = "1.0.0";
