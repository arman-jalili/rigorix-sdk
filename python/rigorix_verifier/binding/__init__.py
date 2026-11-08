"""In-process Rigorix gate over the vendored WASI artifact."""

from __future__ import annotations

from .errors import (
    BindingError,
    GateClosed,
    GateError,
    GateTrap,
    NotWASIArtifact,
)
from .gate import Counters, Gate
from .loader import ARTIFACT_SHA256, ARTIFACT_SIZE, IMPORTS, artifact_bytes

__all__ = [
    "ARTIFACT_SHA256",
    "ARTIFACT_SIZE",
    "BindingError",
    "Counters",
    "Gate",
    "GateClosed",
    "GateError",
    "GateTrap",
    "IMPORTS",
    "NotWASIArtifact",
    "artifact_bytes",
]
