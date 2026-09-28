package dev.rigorix.sdk;

/** Verifier error taxonomy (mirrors the Rust `VerifyError`). */
public class VerifyException extends RuntimeException {

    /** Failure kind, stable for callers that need to branch. */
    public enum Kind {
        SIGNATURE_MISMATCH,
        UNSIGNED_NOT_DEGRADED,
        SCHEMA,
        CHAIN_BROKEN,
        ANCHOR_SIGNATURE
    }

    private final Kind kind;

    public VerifyException(Kind kind, String message) {
        super(message);
        this.kind = kind;
    }

    public Kind kind() {
        return kind;
    }
}
