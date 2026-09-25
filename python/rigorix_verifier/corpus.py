"""Contract-corpus resolution for the Python verifier (SDK-C6 / #21).

Order (mirrors the Rust `rigorix-verifier`):

1. ``RIGORIX_SDK_SCHEMAS`` — an explicit external corpus (CI/local override).
2. The bundled ``rigorix_verifier/_schemas`` directory (a symlink to the repo
   root ``schemas/`` in-tree; dereferenced when the package is built).

There is no repo-relative fallback beyond the bundled copy: a packaged verifier
must not depend on the repository layout.
"""

from __future__ import annotations

import os
from pathlib import Path


def schemas_root() -> Path:
    """Return the directory holding the canonical contract corpus."""
    override = os.environ.get("RIGORIX_SDK_SCHEMAS")
    if override:
        return Path(override)
    bundled = Path(__file__).resolve().parent / "_schemas"
    if bundled.is_dir():
        return bundled
    raise RuntimeError(
        "contract corpus not found: set RIGORIX_SDK_SCHEMAS or bundle "
        "rigorix_verifier/_schemas (the canonical schemas/ corpus)"
    )


def schema_text(rel_path: str) -> str:
    """Return the contract at ``rel_path`` relative to ``schemas/``."""
    return (schemas_root() / rel_path).read_text(encoding="utf-8")


def fixture_text(rel_path: str) -> str:
    """Return the fixture at ``rel_path`` relative to ``schemas/fixtures/``."""
    return (schemas_root() / "fixtures" / rel_path).read_text(encoding="utf-8")


def schema_files() -> list[str]:
    """Every ``.json`` path under ``schemas/`` (relative, sorted)."""
    root = schemas_root()
    return sorted(
        str(p.relative_to(root)).replace(os.sep, "/")
        for p in root.rglob("*.json")
        if p.is_file()
    )
