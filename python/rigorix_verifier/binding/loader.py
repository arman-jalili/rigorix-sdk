"""Resolve and validate the vendored WASI artifact."""

from __future__ import annotations

from importlib import resources

from .errors import NotWASIArtifact

ARTIFACT_NAME = "rigorix_gate_wasi.wasm"

# Recorded in `_wasm/PROVENANCE.md`; the test compares the bytes to this.
ARTIFACT_SHA256 = "7414f8df8772c789b38aeae7460f2f50c816bdde2848bc99470e0b273010bc9c"
ARTIFACT_SIZE = 1_896_910

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
