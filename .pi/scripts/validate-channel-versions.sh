#!/usr/bin/env bash
# validate-channel-versions.sh — the verifier channels must agree.
#
# The verifier ships to four publication channels that must carry one version:
#
#   crates.io         rust/rigorix-verifier/Cargo.toml  [package] version
#   PyPI              python/pyproject.toml + python/rigorix_verifier/__init__.py
#   npm               typescript/package.json
#   Maven Central     java/pom.xml  <project><version>
#
# `rigorix-schemas` and `rigorix-client` are an independent cadence: they carry
# the workspace version and must stay pin-consistent, but they are not verifier
# channels. Locking the verifier to them would force a schema/client release for
# every verifier patch, and the verifier's exact `rigorix-schemas` pin already
# makes its own publish order load-bearing (#55).
#
# The guard fails when the verifier channels disagree, when a required manifest
# is missing, or when an intra-workspace pin does not match the workspace
# version. `--self-test` seeds the drift this repo actually shipped, including
# the #57 three-behind state (npm/Maven/PyPI at 0.8.0 while crates.io is 0.8.1)
# and a stale PyPI `__version__`.
#
# Usage: validate-channel-versions.sh [--root DIR] [--self-test]
set -euo pipefail

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SELF_TEST=0

while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --self-test) SELF_TEST=1; shift ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

read_versions() {
    python3 - "$1" <<'PY'
import json, re, sys, xml.etree.ElementTree as ET
from pathlib import Path

root = Path(sys.argv[1])
channels, independent, problems = [], [], []

def add_channel(channel, path, version):
    if version is None:
        problems.append(f"{channel}: no version found in {path}")
    else:
        channels.append((channel, str(path), str(version).strip()))

def add_independent(channel, path, version, kind):
    if version is None:
        problems.append(f"{channel}: no version found in {path}")
    else:
        independent.append((channel, str(path), str(version).strip(), kind))

# Workspace version — the schemas/client crates inherit it.
ct = root / "rust/Cargo.toml"
workspace_version = None
if ct.exists():
    text = ct.read_text()
    m = re.search(r"^\[workspace\.package\](.*?)(?=^\[|\Z)", text, re.S | re.M)
    if m:
        mv = re.search(r'^version\s*=\s*"([^"]+)"', m.group(1), re.M)
        workspace_version = mv.group(1) if mv else None
    add_independent("crates.io (workspace)", "rust/Cargo.toml", workspace_version, "crate")

# crates.io verifier — its [package] version, which may differ from the
# workspace version while the schema/client cadence stays behind.
vt = root / "rust/rigorix-verifier/Cargo.toml"
if vt.exists():
    text = vt.read_text()
    m = re.search(r"^\[package\](.*?)(?=^\[|\Z)", text, re.S | re.M)
    mv = re.search(r'^version\s*=\s*"([^"]+)"', m.group(1), re.M) if m else None
    add_channel(
        "crates.io (verifier)",
        "rust/rigorix-verifier/Cargo.toml",
        mv.group(1) if mv else None,
    )

# PyPI — two places that must agree, and once did not (a stale __version__).
pp = root / "python/pyproject.toml"
if pp.exists():
    m = re.search(r'^version\s*=\s*"([^"]+)"', pp.read_text(), re.M)
    add_channel("PyPI", "python/pyproject.toml", m.group(1) if m else None)
    init = root / "python/rigorix_verifier/__init__.py"
    if init.exists():
        m = re.search(r'__version__\s*=\s*"([^"]+)"', init.read_text())
        add_channel(
            "PyPI (__version__)",
            "python/rigorix_verifier/__init__.py",
            m.group(1) if m else None,
        )

# npm verifier — the verifier package, not the client.
pkg = root / "typescript/package.json"
if pkg.exists():
    add_channel(
        "npm (verifier)",
        "typescript/package.json",
        json.loads(pkg.read_text()).get("version"),
    )

# npm client — independent cadence.
cpkg = root / "typescript-client/package.json"
if cpkg.exists():
    add_independent(
        "npm (client)",
        "typescript-client/package.json",
        json.loads(cpkg.read_text()).get("version"),
        "crate",
    )

# Maven Central
pom = root / "java/pom.xml"
if pom.exists():
    project = ET.parse(pom).getroot()
    v = next((c.text for c in project if c.tag.rsplit("}", 1)[-1] == "version"), None)
    add_channel("Maven Central", "java/pom.xml", v)

# Intra-workspace pins: each must match the workspace/schemas version. A stale
# one stops the workspace resolving at all, and `cargo publish` was the only
# thing that noticed.
pin_re = re.compile(
    r'\brigorix-(?:schemas|verifier|client)\s*=\s*\{[^}]*?version\s*=\s*"[=^~]?([0-9][^"]*)"'
)
for member in sorted(root.glob("rust/*/Cargo.toml")):
    for m in pin_re.finditer(member.read_text()):
        add_independent(
            f"pin {member.parent.name}",
            str(member.relative_to(root)),
            m.group(1),
            "pin",
        )

print(
    json.dumps(
        {
            "channels": channels,
            "independent": independent,
            "workspace_version": workspace_version,
            "problems": problems,
        }
    )
)
PY
}

check() {
    local root="$1" data rc=0
    data="$(read_versions "$root")"
    python3 - "$data" <<'PY' || rc=$?
import json, sys
d = json.loads(sys.argv[1])
channels = d["channels"]
independent = d["independent"]
problems = d["problems"]
if problems:
    for p in problems:
        print(f"❌ {p}")
    sys.exit(1)
if not channels:
    # An empty scan is a failure, not a pass: nothing compared means nothing checked.
    print("❌ no verifier channel manifests found — check the root")
    sys.exit(1)

width = max(len(c) for c, _, _ in channels)
print("--- Verifier channels (must agree) ---")
for ch, path, v in channels:
    print(f"  {ch:<{width}}  {v:<8} {path}")
uniq = sorted({v for _, _, v in channels})
if len(uniq) > 1:
    print(f"❌ verifier channels disagree: {', '.join(uniq)}")
    sys.exit(1)
print(f"✅ all {len(channels)} verifier channel manifests agree on {uniq[0]}")

workspace_version = d["workspace_version"]
if independent:
    iw = max(len(c) for c, _, _, _ in independent)
    print("--- Independent cadence (reported, not locked) ---")
    for ch, path, v, _kind in independent:
        print(f"  {ch:<{iw}}  {v:<8} {path}")
    pins = [(ch, v) for ch, _path, v, kind in independent if kind == "pin"]
    for ch, v in pins:
        if v != workspace_version:
            print(
                f"❌ {ch} pins {v}, but the workspace/schemas version is {workspace_version}"
            )
            sys.exit(1)
    print(f"✅ {len(pins)} intra-workspace pin(s) match the workspace version")
PY
    return $rc
}

self_test() {
    local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/channel-versions.XXXXXX")"
    for p in rust/Cargo.toml rust/rigorix-verifier/Cargo.toml rust/rigorix-client/Cargo.toml \
             python/pyproject.toml python/rigorix_verifier/__init__.py \
             typescript/package.json typescript-client/package.json java/pom.xml; do
        mkdir -p "$tmp/$(dirname "$p")"; cp "$ROOT/$p" "$tmp/$p"
    done

    local ok=0 bad=0
    if check "$tmp" >/dev/null 2>&1; then ok=$((ok+1)); else
        echo "❌ self-test: a consistent tree was rejected"; fi

    # Seed the drift that shipped: the Java artifact left at an older version.
    python3 - "$tmp/java/pom.xml" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(<artifactId>rigorix-verifier</artifactId>\s*<version>)([^<]+)", r"\g<1>0.0.0", s, count=1)
open(p, "w").write(s)
PY
    if check "$tmp" >/dev/null 2>&1; then
        echo "❌ self-test: a Java version mismatch was accepted"
    else bad=$((bad+1)); fi

    # #57 three-behind: npm still at the previous verifier version.
    cp "$ROOT/java/pom.xml" "$tmp/java/pom.xml"
    python3 - "$tmp/typescript/package.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["version"] = "0.0.0"; json.dump(d, open(p, "w"), indent=2)
PY
    if check "$tmp" >/dev/null 2>&1; then
        echo "❌ self-test: a three-behind npm verifier was accepted"
    else bad=$((bad+1)); fi

    # Stale PyPI __version__ while pyproject moved.
    cp "$ROOT/typescript/package.json" "$tmp/typescript/package.json"
    python3 - "$tmp/python/rigorix_verifier/__init__.py" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'__version__\s*=\s*"[^"]+"', '__version__ = "0.0.0"', s, count=1)
open(p, "w").write(s)
PY
    if check "$tmp" >/dev/null 2>&1; then
        echo "❌ self-test: a stale PyPI __version__ was accepted"
    else bad=$((bad+1)); fi

    # And the other direction: nothing to compare must not be a pass.
    mkdir -p "$tmp/empty"
    if check "$tmp/empty" >/dev/null 2>&1; then
        echo "❌ self-test: an empty root was accepted"
    else bad=$((bad+1)); fi

    # Intra-workspace pin drift: the client pin points at an old schemas crate.
    cp "$ROOT/python/rigorix_verifier/__init__.py" "$tmp/python/rigorix_verifier/__init__.py"
    python3 - "$tmp/rust/rigorix-client/Cargo.toml" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'(rigorix-schemas\s*=\s*\{[^}]*?version\s*=\s*"[=^~]?)([0-9][^"]*)', r'\g<1>0.0.0', s, count=1)
open(p, "w").write(s)
PY
    if check "$tmp" >/dev/null 2>&1; then
        echo "❌ self-test: a stale intra-workspace pin was accepted"
    else bad=$((bad+1)); fi

    find "$tmp" -type f -delete 2>/dev/null || true
    find "$tmp" -depth -type d -empty -delete 2>/dev/null || true

    if [ "$ok" -eq 1 ] && [ "$bad" -eq 5 ]; then
        echo "✅ PASS Channel version self-test: consistent accepted, channel drift rejected, three-behind rejected, stale __version__ rejected, stale pin rejected, empty root rejected"
        return 0
    fi
    echo "❌ FAIL Channel version self-test: ok=$ok rejected=$bad (expected ok=1 rejected=5)"
    return 1
}

if [ "$SELF_TEST" -eq 1 ]; then
    self_test
    exit $?
fi

echo "--- Publication channels ---"
check "$ROOT"
