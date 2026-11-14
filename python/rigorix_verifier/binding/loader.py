"""Resolve and validate the vendored WASI artifact."""

from __future__ import annotations

import hashlib
from importlib import resources

from .errors import ArtifactDigestMismatch, NotWASIArtifact

ARTIFACT_NAME = "rigorix_gate_wasi.wasm"

# Recorded in `_wasm/PROVENANCE.md`; the test compares the bytes to this.
ARTIFACT_SHA256 = "ab77bb821bcff564dd2302a43cf3a73930cfd5ec94925b78328770a8023b7928"
ARTIFACT_SIZE = 1_899_431

#: The exact import section the embedder contract permits.
IMPORTS = (
    ("wasi_snapshot_preview1", "environ_get"),
    ("wasi_snapshot_preview1", "environ_sizes_get"),
    ("wasi_snapshot_preview1", "clock_time_get"),
    ("wasi_snapshot_preview1", "random_get"),
    ("wasi_snapshot_preview1", "fd_write"),
    ("wasi_snapshot_preview1", "proc_exit"),
)

#: The three-export ABI plus the linear memory it reads and writes.
EXPORTS = ("memory", "rigx_alloc", "rigx_call", "rigx_free")


def artifact_bytes() -> bytes:
    """Read the packaged artifact."""
    return (
        resources.files("rigorix_verifier")
        .joinpath("_wasm", ARTIFACT_NAME)
        .read_bytes()
    )


def artifact_digest(raw: bytes) -> str:
    """The digest these bytes have, whether or not they are the recorded ones."""
    return hashlib.sha256(raw).hexdigest()


def verify_artifact(raw: bytes) -> str:
    """Refuse bytes that are not the recorded artifact, and return their digest.

    The import table is cheap to reproduce in a hostile module; the digest is
    not. `Gate.open` calls this before the bytes are compiled, so an installed
    package that was tampered with is a load error, not a different decision.

    The digest is returned because the caller has already paid for it: it is the
    key the compiled module is cached under (#140), and hashing 1.9 MB twice to
    save a tuple would be the same mistake in miniature.
    """
    actual = artifact_digest(raw)
    if len(raw) == ARTIFACT_SIZE and actual == ARTIFACT_SHA256:
        return actual
    raise ArtifactDigestMismatch(ARTIFACT_SHA256, actual, ARTIFACT_SIZE, len(raw))


def validate_module(module) -> None:
    """Refuse anything whose import/export section is not the recorded one.

    An unused capability is still a capability: a seventh import must be a load
    error, named, in the same commit that adds it to the record.
    """
    imports = {(item.module, item.name or "") for item in module.imports}
    expected = set(IMPORTS)

    unexpected = imports - expected
    if unexpected:
        module_name, name = sorted(unexpected)[0]
        raise NotWASIArtifact(
            f"not the WASI artifact: unexpected import {module_name}::{name}"
        )

    missing = expected - imports
    if missing:
        module_name, name = sorted(missing)[0]
        raise NotWASIArtifact(
            f"not the WASI artifact: missing import {module_name}::{name}"
        )

    exports = {item.name for item in module.exports}
    missing_exports = set(EXPORTS) - exports
    if missing_exports:
        raise NotWASIArtifact(
            f"not the WASI artifact: missing export {sorted(missing_exports)[0]}"
        )
