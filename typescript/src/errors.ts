/** Verifier error types (mirrors the Rust `VerifyError` taxonomy). */

export class VerifyError extends Error {}
export class SignatureMismatch extends VerifyError {}
export class UnsignedNotDegraded extends VerifyError {}
export class SchemaViolation extends VerifyError {}
export class ChainBroken extends VerifyError {}
export class AnchorSignature extends VerifyError {}
