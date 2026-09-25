"""Verifier error types (mirrors the Rust `VerifyError` taxonomy)."""

from __future__ import annotations


class VerifyError(Exception):
    """Base class for every verification failure."""


class SignatureMismatch(VerifyError):
    """The HMAC over the canonical bytes does not match the signature."""


class UnsignedNotDegraded(VerifyError):
    """A null signature without ``evidence_degraded=true`` (GAP-M-12)."""


class SchemaViolation(VerifyError):
    """The instance does not conform to the named JSON Schema."""


class ChainBroken(VerifyError):
    """A per-producer chain gap/reorder/insertion or ``prev_hash`` mismatch."""


class AnchorSignature(VerifyError):
    """An anchor artifact's Ed25519 signature did not verify."""
