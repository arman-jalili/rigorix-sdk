#!/usr/bin/env python3
"""Materialise the canonical contract corpus into
``python/rigorix_verifier/_schemas`` as a REAL directory, because setuptools
does **not** dereference the repo-root ``schemas/`` symlink into the
wheel/sdist.

The source of truth stays ``<repo>/schemas``; this copy is generated (and
gitignored). Run from the setuptools build hooks (`setup.py`) and pytest.
Mirrors what ``cargo package`` does for the Rust ``rigorix-schemas`` crate
(SDK-C6-PACKAGING).
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent  # python/scripts
PACKAGE_ROOT = HERE.parent  # python/
REPO_ROOT = PACKAGE_ROOT.parent  # repo root
SOURCE = REPO_ROOT / "schemas"
TARGET = PACKAGE_ROOT / "rigorix_verifier" / "_schemas"


def bundle() -> int:
    """Copy ``schemas/`` into the package as a real directory. Idempotent.

    When building the wheel from an sdist, the canonical repo-root ``schemas/``
    is absent but the sdist already carries the bundled
    ``rigorix_verifier/_schemas`` — accept that as the source (no-op).
    """
    if not SOURCE.is_dir():
        if TARGET.is_dir() and not TARGET.is_symlink():
            print("bundle_schemas: canonical corpus absent; using the pre-bundled copy")
            return 0
        print(f"bundle_schemas: canonical corpus not found at {SOURCE}", file=sys.stderr)
        return 1
    if TARGET.is_symlink() or TARGET.is_file():
        TARGET.unlink()
    elif TARGET.exists():
        shutil.rmtree(TARGET)
    shutil.copytree(SOURCE, TARGET)
    count = sum(1 for path in TARGET.rglob("*") if path.is_file())
    print(f"bundle_schemas: {count} files -> {TARGET.relative_to(PACKAGE_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(bundle())
