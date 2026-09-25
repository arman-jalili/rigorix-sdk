//! Device-flow auth helpers (ADR-0008): thin conveniences over
//! `rigorix.auth.*`. The client never invents identity — the attested session
//! is authoritative (ADR-0001 D5); `approver_id`/`authority` are display-only.

use crate::client::Client;
use crate::error::ClientError;
use crate::transport::Transport;
use crate::types::{AuthLoginParams, AuthLoginResult, AuthStatusResult};

/// Begin the OIDC device flow (`rigorix.auth.login`).
pub fn begin_device_flow<T: Transport>(
    client: &Client<T>,
    params: &AuthLoginParams,
) -> Result<AuthLoginResult, ClientError> {
    client.auth_login(params)
}

/// Report the redacted session status (`rigorix.auth.status`).
pub fn session_status<T: Transport>(client: &Client<T>) -> Result<AuthStatusResult, ClientError> {
    client.auth_status()
}
