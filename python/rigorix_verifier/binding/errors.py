"""Typed failures for the in-process gate binding."""

from __future__ import annotations


class BindingError(Exception):
    """Base class for binding failures."""


class NotWASIArtifact(BindingError):
    """The bytes are not the `rigx_*` WASI artifact, or their imports differ."""


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
