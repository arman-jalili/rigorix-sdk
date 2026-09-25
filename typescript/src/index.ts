/** rigorix-verifier (TypeScript) — Strategy A parity for the signed audit trail.
 *
 * Independent, protocol-only verification: HMAC-SHA256 over the canonical
 * form, JSON Schema conformance, ADR-016 per-producer chains, and Ed25519
 * anchor artifacts. No engine dependency; the contract corpus comes from the
 * bundled `_schemas`/`RIGORIX_SDK_SCHEMAS` copy.
 */

export * from "./anchor.js";
export * from "./canonical.js";
export * from "./chain.js";
export * from "./corpus.js";
export * from "./envelope.js";
export * from "./errors.js";
