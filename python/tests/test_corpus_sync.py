"""The generated `_schemas` copy must stay byte-equal to the canonical corpus."""

from __future__ import annotations

import os
from pathlib import Path

from rigorix_verifier import corpus


def _snapshot(root: Path) -> dict[str, bytes]:
    return {str(path.relative_to(root)): path.read_bytes() for path in root.rglob("*") if path.is_file()}


def test_materialised_corpus_matches_canonical() -> None:
    if os.environ.get("RIGORIX_SDK_SCHEMAS"):
        return  # explicit override: nothing to compare
    bundled = corpus.schemas_root()
    # tests/ -> python/ -> repo root
    canonical = Path(__file__).resolve().parent.parent.parent / "schemas"
    assert canonical.is_dir()
    assert _snapshot(bundled) == _snapshot(canonical)
