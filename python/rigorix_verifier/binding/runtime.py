"""Which wasm engine made the decision, and which one is pinned.

The artifact answers `contract_version`; the engine is the process's own
dependency, so its version is read from the installed distribution. Reporting it
beside the artifact digest and the contract is what lets a support case say
which of the three numbers changed.
"""

from __future__ import annotations

from importlib import metadata


def runtime_version() -> str:
    """The installed `wasmtime` version, e.g. `50.0.1`."""
    return metadata.version("wasmtime")