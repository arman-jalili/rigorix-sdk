"""Setuptools build hooks that materialise the contract corpus before packaging.

setuptools does not dereference the repo-root ``schemas/`` symlink into the
wheel/sdist, so we copy it into ``rigorix_verifier/_schemas`` (a generated,
gitignored real directory) before ``build_py`` and ``sdist`` run. See
``scripts/bundle_schemas.py`` (SDK-C6-PACKAGING).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from setuptools import setup
from setuptools.command.build_py import build_py as _build_py
from setuptools.command.sdist import sdist as _sdist

HERE = Path(__file__).resolve().parent


def bundle() -> None:
    subprocess.check_call([sys.executable, str(HERE / "scripts" / "bundle_schemas.py")])


class build_py(_build_py):
    def run(self) -> None:
        bundle()
        super().run()


class sdist(_sdist):
    def run(self) -> None:
        bundle()
        super().run()


setup(cmdclass={"build_py": build_py, "sdist": sdist})
