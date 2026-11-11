#!/usr/bin/env python3
"""govulncheck, with a policy about what this tree can fix (#112).

`govulncheck ./...` answers one question — is a vulnerable symbol reached — and exits
non-zero for any finding. That made the gate a property of the advisory feed rather
than of the tree: `go 1.26` was red on 1.26.3, `go 1.26.10` was red on the next
stdlib advisory, and each new publication moved the bar. The floor cannot chase an
advisory that lands yesterday, and a gate that is red for a reason the branch cannot
address teaches people to ignore it.

The policy, applied to every finding govulncheck reports:

* **actionable here** — the fix is inside the declared minor (a stdlib patch the
  floor can name) or it is a module version (a dependency this tree can bump). The
  step fails and prints the version to name.
* **not actionable here** — the fix exists only in a later Go minor. The step prints
  the version that would be needed and does not fail, because raising a language
  minor is a decision, not a patch.

Both numbers are printed either way, so the log says what was found and what would
fix it. A finding that cannot be parsed fails closed.

Modes:
    govulncheck.py              run the scan and apply the policy
    govulncheck.py --self-test  the three classifications, from fixtures
    govulncheck.py --check-floor the stale-floor watch for the scheduled job: report
                                when the declared floor is behind the newest patch of
                                its minor; never fails (nothing is opened for it)
    govulncheck.py --go-dir DIR point the scan at another module (the seeds use it)
    govulncheck.py --scan-module apply the policy to `-scan=module` instead of `./...`:
                                findings in packages the code does not call. Not the
                                gate — the gate is symbol-level — but the mode the seed
                                uses, because a planted module is by construction not
                                called and `./...` would rightly find nothing.

Usage: python3 scripts/govulncheck.py [--self-test | --check-floor]
Exit: 0 = clean, or only findings a later minor fixes; 1 = an actionable finding;
      2 = govulncheck (or the network, for --check-floor) is unavailable.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GO_DIR = Path(
    sys.argv[sys.argv.index("--go-dir") + 1] if "--go-dir" in sys.argv else ROOT / "go"
).resolve()
GO_MOD = GO_DIR / "go.mod"

FLOOR_RE = re.compile(r"^go (\d+)\.(\d+)\.(\d+)\s*$", re.MULTILINE)
VULN_HEADER_RE = re.compile(r"^Vulnerability #\d+: (GO-\d{4}-\d+)$", re.MULTILINE)
FIXED_RE = re.compile(r"^\s+Fixed in:\s+(\S+)$", re.MULTILINE)
FIXED_VERSION_RE = re.compile(r"@(?:go)?(\d+)\.(\d+)\.(\d+)$")


def floor() -> tuple[int, int, int]:
    match = FLOOR_RE.search(GO_MOD.read_text(encoding="utf-8"))
    if match is None:
        raise SystemExit("govulncheck: go/go.mod has no `go X.Y.Z` floor")
    return tuple(int(part) for part in match.groups())  # type: ignore[return-value]


def vulns(output: str) -> list[dict]:
    """Split govulncheck's report into findings with their fix versions."""
    findings: list[dict] = []
    headers = list(VULN_HEADER_RE.finditer(output))
    for index, header in enumerate(headers):
        end = headers[index + 1].start() if index + 1 < len(headers) else len(output)
        block = output[header.end():end]
        fixed = [entry.strip() for entry in FIXED_RE.findall(block)]
        found = re.findall(r"^\s+Found in:\s+(\S+)$", block, re.MULTILINE)
        findings.append({"id": header.group(1), "fixed": fixed, "found": found})
    return findings


def classify(finding: dict, declared: tuple[int, int, int]) -> tuple[bool, str]:
    """(actionable, the version to name) for one finding."""
    if not finding["fixed"]:
        return True, "no fixed version is published — treat as actionable"
    actionable: list[str] = []
    later: list[str] = []
    for entry in finding["fixed"]:
        match = FIXED_VERSION_RE.search(entry)
        if match is None:
            # A module version (golang.org/x/text@v0.15.0): the tree can bump it.
            actionable.append(entry)
            continue
        version = tuple(int(part) for part in match.groups())
        if version[:2] == declared[:2]:
            actionable.append(entry)
        elif version[:2] > declared[:2]:
            later.append(entry)
        else:
            # A fix on an *older* line than the floor: the floor already carries it.
            continue
    if actionable:
        return True, ", ".join(sorted(set(actionable)))
    if later:
        return False, ", ".join(sorted(set(later)))
    return False, "the declared floor already carries the fix"


def report(output: str, declared: tuple[int, int, int]) -> int:
    findings = vulns(output)
    if not findings:
        if "No vulnerabilities found" in output:
            print("✅ govulncheck: no vulnerabilities found")
            return 0
        # Non-zero with nothing parseable: fail closed rather than pass on a parse.
        print("❌ govulncheck failed and its report could not be parsed")
        print(output.rstrip())
        return 1

    actionable = 0
    for finding in findings:
        is_actionable, version = classify(finding, declared)
        found = ", ".join(finding["found"]) or "unknown package"
        if is_actionable:
            actionable += 1
            print(f"❌ {finding['id']} — {found}")
            print(f"   actionable here: fix with {version} (the floor is go {'.'.join(map(str, declared))})")
        else:
            print(f"⚠ {finding['id']} — {found}")
            print(f"   not actionable by this tree: fixed only in {version}, a later minor")
    if actionable:
        print(
            f"❌ {actionable} actionable finding(s): name a newer patch in go/go.mod "
            f"(currently go {'.'.join(map(str, declared))}), or fix the dependency"
        )
        return 1
    print(
        f"✅ govulncheck: {len(findings)} finding(s), none fixable inside go "
        f"{declared[0]}.{declared[1]} — reported, not failed"
    )
    return 0


def run(scan_module: bool = False) -> int:
    binary = shutil.which("govulncheck")
    if binary is None:
        candidate = Path(subprocess.run(["go", "env", "GOPATH"], capture_output=True, text=True).stdout.strip() or "/nonexistent")
        binary = str(candidate / "bin" / "govulncheck")
        if not Path(binary).exists():
            print("govulncheck: not installed (go install golang.org/x/vuln/cmd/govulncheck@latest)", file=sys.stderr)
            return 2
    # Inside the module: with GOTOOLCHAIN=auto, `go` switches to the floor's patch,
    # and the printed toolchain must be the one that builds — the stdlib the scan
    # reports belongs to that toolchain, not to whatever is first on PATH.
    toolchain = subprocess.run(
        ["go", "version"], cwd=GO_DIR, capture_output=True, text=True
    ).stdout.strip()
    print(f"toolchain: {toolchain}")
    declared = floor()
    if scan_module:
        # The seed's mode: a planted module is never called, so `./...` is silent by
        # design and only the graph shows it. Applying the same policy here proves the
        # classification, not the symbol reachability.
        result = subprocess.run([binary, "-scan=module"], cwd=GO_DIR, capture_output=True, text=True)
        return report(result.stdout + result.stderr, declared)

    result = subprocess.run(
        [binary, "./..."], cwd=GO_DIR, capture_output=True, text=True
    )
    output = result.stdout + result.stderr
    verdict = report(output, declared)
    # Uncalled advisories are reported, never swallowed.
    module = subprocess.run([binary, "-scan=module"], cwd=GO_DIR, capture_output=True, text=True)
    print("--- module scope (informational: advisories the code does not call) ---")
    print((module.stdout + module.stderr).strip() or "(none)")
    return verdict


def newest_patch(minor: tuple[int, int]) -> int | None:
    url = "https://go.dev/dl/?mode=json&include=all"
    try:
        with urllib.request.urlopen(url, timeout=20) as response:
            releases = json.load(response)
    except Exception:
        return None
    patches = []
    for release in releases:
        match = re.fullmatch(r"go(\d+)\.(\d+)\.(\d+)", release.get("version", ""))
        if match and (int(match.group(1)), int(match.group(2))) == minor:
            patches.append(int(match.group(3)))
    return max(patches) if patches else None


def check_floor() -> int:
    declared = floor()
    newest = newest_patch((declared[0], declared[1]))
    if newest is None:
        print(
            f"⚠ not verified: the release index could not be read, so the floor "
            f"(go {'.'.join(map(str, declared))}) was not compared",
            file=sys.stderr,
        )
        return 2
    if newest > declared[2]:
        print(
            f"⚠ the floor is behind: go {declared[0]}.{declared[1]}.{newest} is published "
            f"and go/go.mod says {'.'.join(map(str, declared))} — a stdlib advisory fixed "
            f"there is invisible to a branch"
        )
        return 0
    print(f"✅ floor: go {'.'.join(map(str, declared))} is the newest patch of its minor")
    return 0


def self_test() -> int:
    declared = (1, 26, 11)
    cases = 0
    failures = 0

    def case(label: str, output: str, expected: int) -> None:
        nonlocal cases, failures
        cases += 1
        actual = report(output, declared)
        if actual != expected:
            print(f"❌ self-test [{label}]: exit {actual}, expected {expected}")
            failures += 1

    clean = "No vulnerabilities found."
    case("clean", clean, 0)
    case(
        "fixed inside the minor",
        "Vulnerability #1: GO-2026-9001\n"
        "    Found in: net/http@go1.26.11\n"
        "    Fixed in: net/http@go1.26.12\n"
        "Your code is affected by 1 vulnerability from the Go standard library.\n",
        1,
    )
    case(
        "fixed only in a later minor",
        "Vulnerability #1: GO-2026-9002\n"
        "    Found in: crypto/x509@go1.26.11\n"
        "    Fixed in: crypto/x509@go1.27.1\n"
        "Your code is affected by 1 vulnerability from the Go standard library.\n",
        0,
    )
    case(
        "a module dependency",
        "Vulnerability #1: GO-2026-9003\n"
        "    Found in: golang.org/x/text@v0.14.0\n"
        "    Fixed in: golang.org/x/text@v0.41.0\n",
        1,
    )
    case("unparseable failure", "govulncheck: something went wrong\n", 1)

    if failures:
        print(f"❌ govulncheck self-test: {failures} of {cases} case(s) wrong")
        return 1
    print(
        f"✅ govulncheck self-test: {cases} cases — a patch inside the minor and a module "
        "bump are actionable, a later minor is reported, an unparseable failure fails closed"
    )
    return 0


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return self_test()
    if "--check-floor" in sys.argv[1:]:
        return check_floor()
    return run(scan_module="--scan-module" in sys.argv[1:])


if __name__ == "__main__":
    sys.exit(main())