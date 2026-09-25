"""Materialise the contract corpus before the test session.

The repo no longer commits a ``_schemas`` symlink: the corpus is generated into
``rigorix_verifier/_schemas`` (a real, gitignored directory) so tests and the
packed artifact both read a real copy (SDK-C6-PACKAGING).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def pytest_sessionstart(session) -> None:  # noqa: ARG001 (pytest hook signature)
    script = Path(__file__).resolve().parent / "scripts" / "bundle_schemas.py"
    subprocess.check_call([sys.executable, str(script)])
