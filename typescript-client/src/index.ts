// SPDX-License-Identifier: Apache-2.0
/** rigorix-client (TypeScript) — protocol-only typed client for the frozen
 * `rigorix.*` JSON-RPC catalog (ADR-0001). Governed flows only; no raw step
 * execution; no engine dependency. */

export * from "./auth.js";
export * from "./catalog.js";
export * from "./client.js";
export * from "./error.js";
export * from "./jsonrpc.js";
export * from "./transport.js";
export type * from "./types.js";
