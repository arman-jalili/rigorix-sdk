/** Device-flow auth helpers (ADR-0008): conveniences over `rigorix.auth.*`.
 * The client never invents identity — the attested session is authoritative
 * (ADR-0001 D5); `approver_id`/`authority` are display-only. */

import type { Client } from "./client.js";
import type { AuthLoginParams, AuthLoginResult, AuthStatusResult } from "./types.js";

/** Begin the OIDC device flow (`rigorix.auth.login`). */
export function beginDeviceFlow(
  client: Client,
  params: AuthLoginParams,
): Promise<AuthLoginResult> {
  return client.authLogin(params);
}

/** Report the redacted session status (`rigorix.auth.status`). */
export function sessionStatus(client: Client): Promise<AuthStatusResult> {
  return client.authStatus();
}
