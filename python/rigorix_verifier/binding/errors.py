"""Typed failures for the in-process gate binding."""

from __future__ import annotations


class BindingError(Exception):
    """Base class for binding failures."""


class NotWASIArtifact(BindingError):
    """The bytes are not the `rigx_*` WASI artifact, or their imports differ."""


class ArtifactDigestMismatch(NotWASIArtifact):
    """The bytes are not the recorded artifact; the error names both digests."""

    def __init__(self, expected: str, actual: str, expected_size: int, actual_size: int) -> None:
        super().__init__(
            "artifact digest mismatch: "
            f"expected {expected} ({expected_size} bytes), "
            f"got {actual} ({actual_size} bytes)"
        )
        self.expected = expected
        self.actual = actual
        self.expected_size = expected_size
        self.actual_size = actual_size


class GateClosed(BindingError):
    """The session was sealed; a stale handle is never sent down."""


class GateTrap(BindingError):
    """The artifact trapped (including `proc_exit`); a trap is not a refusal."""


class GateError(BindingError):
    """The artifact returned a typed refusal (a JSON object with `kind`)."""

    def __init__(self, kind: str, message: str) -> None:
        super().__init__(f"gate: {kind}: {message}")
        self.kind = kind
        self.message = message
