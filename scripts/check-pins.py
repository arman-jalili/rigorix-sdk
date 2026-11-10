#!/usr/bin/env python3
"""Fail on a range where an exact runtime pin is required (SDL-5 / #69).

A pin is what makes "the recorded runtime version" a fact: `wasmtime==50.0.1`
and `wazero v1.12.0` are claims a support case can quote. `wasmtime>=20.0` is a
claim about nothing — the installed engine may be any of 50 releases, and the
provenance would still read as if it named one.

Scope: the two wasm engines, plus the Go module's floor. The floor belongs here
because, like a pin, it is a claim about a version: `go 1.26` is a *minimum
language version*, so it admits 1.26.3 — a toolchain whose standard library
carries 17 advisories, which made `govulncheck` fail on a host the module called
in-policy (#98). A floor must name a patch release for the gate to be a property
of the tree.

The two wasm engines are, because those are the versions recorded in
`PROVENANCE.md` and reported at run time by `binding.runtime_version()`.
Ordinary library dependencies keep their compatible ranges; a library that
pinned `jsonschema` exactly would fight its consumers, and it is not the thing
whose version appears in an incident report.

Usage:
    python scripts/check-pins.py

Exit: 0 = the engines are pinned exactly and the provenance agrees; 1 = a range,
a missing pin, or a provenance/runtime disagreement (the message quotes the line).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

PYPROJECT = ROOT / "python" / "pyproject.toml"
GO_MOD = ROOT / "go" / "go.mod"
PY_PROVENANCE = ROOT / "python" / "rigorix_verifier" / "_wasm" / "PROVENANCE.md"
GO_PROVENANCE = ROOT / "go" / "gate" / "testdata" / "PROVENANCE.md"

WASMTIME = "wasmtime"
WAZERO = "github.com/tetratelabs/wazero"

#: Operators that make a requirement a range rather than a pin.
RANGE_MARKERS = (">=", "<=", ">", "<", "~=", "!=", "^", "~", "*")

PIN_RE = re.compile(r"^==\s*(\d+\.\d+\.\d+)$")
GO_PIN_RE = re.compile(r"^v(\d+\.\d+\.\d+)$")
GO_FLOOR_RE = re.compile(r"^go (\d+\.\d+\.\d+)$", re.MULTILINE)


class PinError(Exception):
    def __init__(self, path: Path, line_number: int, line: str, message: str) -> None:
        super().__init__(f"{path.relative_to(ROOT)}:{line_number}: {message}\n    {line.strip()}")


def _line_of(text: str, needle: str) -> int:
    """1-based line number of the first line containing `needle`."""
    for number, line in enumerate(text.splitlines(), start=1):
        if needle in line:
            return number
    return 1


def _python_requirements(text: str) -> list[tuple[int, str]]:
    """(line number, requirement) for every entry in [project].dependencies."""
    start = re.search(r"^dependencies\s*=\s*\[", text, re.MULTILINE)
    if start is None:
        raise PinError(PYPROJECT, 1, text.splitlines()[0], "no [project].dependencies array")
    block_start = start.end()
    end = text.find("]", block_start)
    if end == -1:
        raise PinError(PYPROJECT, _line_of(text, "dependencies"), "dependencies = [", "unterminated array")

    requirements = []
    offset = block_start
    for raw in text[block_start:end].split(","):
        entry = raw.strip().strip('"').strip("'").strip()
        if entry and not entry.startswith("#"):
            requirements.append((_line_of(text, entry) if entry in text else 1, entry))
        offset += len(raw) + 1
    return requirements


def check_wasmtime() -> str:
    text = PYPROJECT.read_text(encoding="utf-8")
    found = None
    for number, entry in _python_requirements(text):
        name = re.split(r"[<>=!~\[ ;]", entry, maxsplit=1)[0].strip()
        if name != WASMTIME:
            continue
        found = (number, entry)
        specifier = entry[len(name) :].strip()
        if any(marker in specifier for marker in RANGE_MARKERS):
            raise PinError(
                PYPROJECT,
                number,
                entry,
                f"{WASMTIME} must be pinned exactly (==X.Y.Z), not a range",
            )
        match = PIN_RE.match(specifier)
        if not match:
            raise PinError(
                PYPROJECT,
                number,
                entry,
                f"{WASMTIME} must be pinned as ==X.Y.Z (e.g. ==50.0.1)",
            )
        return match.group(1)

    raise PinError(
        PYPROJECT,
        _line_of(text, "dependencies"),
        "dependencies = [",
        f"no {WASMTIME} pin found; the binding's runtime must be named",
    )


def check_wazero() -> str:
    text = GO_MOD.read_text(encoding="utf-8")
    for number, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped.startswith(WAZERO):
            continue
        version = stripped.split()[1] if len(stripped.split()) > 1 else ""
        if any(marker in version for marker in RANGE_MARKERS):
            raise PinError(GO_MOD, number, line, f"{WAZERO} must be pinned exactly (vX.Y.Z)")
        match = GO_PIN_RE.match(version)
        if not match:
            raise PinError(GO_MOD, number, line, f"{WAZERO} must carry a vX.Y.Z pin")
        return match.group(1)
    raise PinError(GO_MOD, 1, "module", f"no {WAZERO} requirement found")


def go_floor(text: str) -> str:
    """The `go` directive, which must name a patch release (X.Y.Z)."""
    match = GO_FLOOR_RE.search(text)
    if match:
        return match.group(1)
    minor = re.search(r"^go (\d+\.\d+)\s*$", text, re.MULTILINE)
    if minor:
        raise PinError(
            GO_MOD,
            _line_of(text, f"go {minor.group(1)}"),
            f"go {minor.group(1)}",
            "the go directive must name a patch release (e.g. go 1.26.10), not a minor: "
            "a minor admits a toolchain whose stdlib the scan then reports",
        )
    raise PinError(GO_MOD, 1, text.splitlines()[0], "no `go` directive: the floor cannot be read")


def check_go_floor() -> str:
    return go_floor(GO_MOD.read_text(encoding="utf-8"))


def self_test() -> int:
    """The floor's own cases: a patch passes, a minor fails, absence fails."""
    failures = 0
    if go_floor("module x\n\ngo 1.26.10\n") != "1.26.10":
        print("❌ self-test: a patch floor was not accepted", file=sys.stderr)
        failures += 1
    for text, expects in (("module x\n\ngo 1.26\n", "patch release"), ("module x\n", "no `go` directive")):
        try:
            go_floor(text)
        except PinError as error:
            if expects not in str(error):
                print(f"❌ self-test: wrong reason: {error}", file=sys.stderr)
                failures += 1
        else:
            print(f"❌ self-test: {text.splitlines()[-1]!r} was accepted", file=sys.stderr)
            failures += 1
    if failures:
        return 1
    print("✅ check-pins self-test: a minor floor is refused, a patch floor is accepted")
    return 0


def check_provenance(pin: str) -> None:
    """The provenance names the runtime, and names the pinned one."""
    text = PY_PROVENANCE.read_text(encoding="utf-8")
    if not re.search(r"^## Runtime\s*$", text, re.MULTILINE):
        raise PinError(PY_PROVENANCE, 1, "# rigorix_gate_wasi.wasm", "no '## Runtime' section")
    if f"{WASMTIME}=={pin}" not in text:
        raise PinError(
            PY_PROVENANCE,
            _line_of(text, "## Runtime"),
            "## Runtime",
            f"the provenance must name {WASMTIME}=={pin} (the pin in pyproject.toml)",
        )


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return self_test()
    try:
        wasmtime = check_wasmtime()
        wazero = check_wazero()
        floor = check_go_floor()
        check_provenance(wasmtime)
    except PinError as error:
        print(f"❌ {error}", file=sys.stderr)
        return 1
    print(
        f"✅ exact runtime pins: {WASMTIME}=={wasmtime}, {WAZERO} v{wazero}; "
        f"provenance agrees; go floor {floor}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())