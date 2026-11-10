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

Two more subjects, for the same reason (#105): a workflow `uses:` that names a tag
or a branch executes code that can change without a commit here — including the
action holding the PyPI token — and a secret scanner pinned by tag can be a
different scanner under the same name tomorrow. GitHub's own hardening guidance is
SHA pinning with the version in a trailing comment; this repository's standard is
already "a pin is a digest", so the workflows answer to it too.

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

WORKFLOWS = ROOT / ".github" / "workflows"
SECRETS_SCRIPT = ROOT / "scripts" / "check-secrets.sh"
USES_RE = re.compile(r"^\s*(?:-\s*)?uses:\s*([^@\s]+)@(\S+?)\s*(?:#\s*(.*?))?\s*$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
GITLEAKS_RE = re.compile(r'GITLEAKS_IMAGE="\$\{GITLEAKS_IMAGE:-([^}]+)\}')
DIGEST_RE = re.compile(r"@sha256:[0-9a-f]{64}$")


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


def workflow_pin_errors(text: str, label: str) -> list[str]:
    """Every `uses:` line that is not a 40-hex commit with a version comment."""
    errors = []
    for number, line in enumerate(text.splitlines(), start=1):
        match = USES_RE.match(line)
        if match is None:
            continue
        action, ref, comment = match.group(1), match.group(2), match.group(3) or ""
        if not SHA_RE.match(ref):
            errors.append(
                f"{label}:{number}: uses: {action}@{ref} is not a commit SHA — a tag "
                "or branch can move; pin the 40-hex commit and put the version in a comment"
            )
        elif not comment.strip():
            errors.append(
                f"{label}:{number}: uses: {action}@{ref} has no version comment — the "
                "SHA says what runs, the comment says what it is"
            )
    return errors


def gitleaks_pin_error(text: str, label: str = "scripts/check-secrets.sh") -> str | None:
    """The scanner image must be a digest, not a tag."""
    match = GITLEAKS_RE.search(text)
    if match is None:
        return f"{label}: no GITLEAKS_IMAGE default found — the scanner must be named"
    image = match.group(1)
    if not DIGEST_RE.search(image):
        return (
            f"{label}: GITLEAKS_IMAGE is {image} — a tag can be moved, and then the "
            "same command runs a different scanner (pin @sha256:<digest>, tag in the comment)"
        )
    return None


def check_workflow_pins() -> list[str]:
    errors: list[str] = []
    files = sorted(WORKFLOWS.glob("*.yml")) + sorted(WORKFLOWS.glob("*.yaml"))
    if not files:
        errors.append(".github/workflows: no subject, not evidence — no workflow file found")
    for path in files:
        errors.extend(workflow_pin_errors(path.read_text(encoding="utf-8"), str(path.relative_to(ROOT))))
    return errors


def check_gitleaks_pin() -> str | None:
    return gitleaks_pin_error(SECRETS_SCRIPT.read_text(encoding="utf-8"))


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
    """Each rule's own cases: a pinned shape passes, an unpinned one fails."""
    failures = 0
    sha = "0" * 40

    # #105: a tag and a missing version comment are two different defects.
    planted = "      - uses: actions/checkout@v4\n"
    errors = workflow_pin_errors(planted, "planted.yml")
    if not errors or "is not a commit SHA" not in errors[0]:
        print("❌ self-test: an action pinned by tag was accepted", file=sys.stderr)
        failures += 1
    if workflow_pin_errors(f"      - uses: actions/checkout@{sha}  # v4\n", "planted.yml"):
        print("❌ self-test: a SHA-pinned action with a version comment was refused", file=sys.stderr)
        failures += 1
    if not workflow_pin_errors(f"      - uses: actions/checkout@{sha}\n", "planted.yml"):
        print("❌ self-test: a SHA without a version comment was accepted", file=sys.stderr)
        failures += 1

    for image, ok in (("zricethezav/gitleaks:v8.30.1", False),
                      (f"zricethezav/gitleaks@sha256:{'a' * 64}", True)):
        text = f'GITLEAKS_IMAGE="${{GITLEAKS_IMAGE:-{image}}}"\n'
        error = gitleaks_pin_error(text)
        if ok and error:
            print(f"❌ self-test: digest-pinned image refused: {error}", file=sys.stderr)
            failures += 1
        if not ok and not error:
            print("❌ self-test: a tag-pinned scanner was accepted", file=sys.stderr)
            failures += 1

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
    print(
        "✅ check-pins self-test: a minor floor, an action tag, an uncommented SHA and a "
        "tag-pinned scanner are each refused; the pinned shapes are accepted"
    )
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
    # Both subjects are reported together: a fix that satisfies one and misses the
    # other should be one run, not two.
    pin_errors = check_workflow_pins()
    gitleaks_error = check_gitleaks_pin()
    if gitleaks_error:
        pin_errors.append(gitleaks_error)
    if pin_errors:
        for error in pin_errors:
            print(f"❌ {error}", file=sys.stderr)
        return 1
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
        f"provenance agrees; go floor {floor}; every workflow action pinned by SHA; "
        "the secret scanner by digest"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())