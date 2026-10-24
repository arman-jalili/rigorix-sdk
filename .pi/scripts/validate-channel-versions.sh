#!/usr/bin/env bash
# validate-channel-versions.sh — the five publication channels must agree.
#
# The SDK ships one version to five registries:
#
#   crates.io         rust/Cargo.toml  [workspace.package] version   (+ rust-v tag)
#   PyPI              python/pyproject.toml + python/rigorix_verifier/__init__.py
#   npm               typescript/package.json
#   npm (client)      typescript-client/package.json
#   Maven Central     java/pom.xml  <project><version>
#   Go                go/go.mod — tag-only: `go/vX.Y.Z`
#
# Nothing compared them until this script existed, and the drift was real: the Java
# artifact sat at 0.2.0 while every other channel was at 0.6.0, so a release would
# have published five registries at two different versions — with no test failing.
#
# A release whose version numbers disagree is not a smaller release, it is a broken
# one: consumers resolve one version and get artifacts from another.
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
out, problems = [], []

def add(channel, path, version):
    if version is None:
        problems.append(f"{channel}: no version found in {path}")
    else:
        out.append((channel, str(path), version.strip()))

# crates.io — [workspace.package] version, which every member inherits.
ct = root / "rust/Cargo.toml"
if ct.exists():
    text = ct.read_text()
    m = re.search(r"^\[workspace\.package\](.*?)(?=^\[|\Z)", text, re.S | re.M)
    v = None
    if m:
        mv = re.search(r'^version\s*=\s*"([^"]+)"', m.group(1), re.M)
        v = mv.group(1) if mv else None
    add("crates.io", "rust/Cargo.toml", v)

# PyPI — two places that must agree, and once did not (a stale __version__).
pp = root / "python/pyproject.toml"
if pp.exists():
    m = re.search(r'^version\s*=\s*"([^"]+)"', pp.read_text(), re.M)
    add("PyPI", "python/pyproject.toml", m.group(1) if m else None)
    init = root / "python/rigorix_verifier/__init__.py"
    if init.exists():
        m = re.search(r'__version__\s*=\s*"([^"]+)"', init.read_text())
        add("PyPI (__version__)", "python/rigorix_verifier/__init__.py", m.group(1) if m else None)

# npm — verifier and client are separate packages, published separately.
for pkg in ("typescript/package.json", "typescript-client/package.json"):
    p = root / pkg
    if p.exists():
        add("npm", pkg, json.loads(p.read_text()).get("version"))

# Maven Central
pom = root / "java/pom.xml"
if pom.exists():
    # The POM declares the maven namespace, so a bare findtext("version") returns
    # nothing — match on the local name instead.
    project = ET.parse(pom).getroot()
    v = next((c.text for c in project if c.tag.rsplit("}", 1)[-1] == "version"), None)
    add("Maven Central", "java/pom.xml", v)

# Intra-workspace pins. These are not publication channels, but a stale one stops
# the workspace resolving at all — rigorix-client still required ^0.7.0 while the
# crates were at 0.8.0, and only `cargo publish` found it. A version guard that
# does not read them is checking the outside and ignoring the inside.
pin_re = re.compile(
    r'\brigorix-(?:schemas|verifier|client)\s*=\s*\{[^}]*?version\s*=\s*"[=^~]?([0-9][^"]*)"'
)
for member in sorted(root.glob("rust/*/Cargo.toml")):
    for m in pin_re.finditer(member.read_text()):
        add(f"pin {member.parent.name}", str(member.relative_to(root)), m.group(1))

print(json.dumps({"versions": out, "problems": problems}))
PY
}

check() {
    local root="$1" data rc=0
    data="$(read_versions "$root")"
    python3 - "$data" <<'PY' || rc=$?
import json, sys
d = json.loads(sys.argv[1])
rows = d["versions"]
if d["problems"]:
    for p in d["problems"]:
        print(f"❌ {p}")
    sys.exit(1)
if not rows:
    # An empty scan is a failure, not a pass: nothing compared means nothing checked.
    print("❌ no channel manifests found — check the root")
    sys.exit(1)
width = max(len(c) for c, _, _ in rows)
for ch, path, v in rows:
    print(f"  {ch:<{width}}  {v:<8} {path}")
uniq = sorted({v for _, _, v in rows})
if len(uniq) > 1:
    print(f"❌ channels disagree: {', '.join(uniq)}")
    sys.exit(1)
print(f"✅ all {len(rows)} channel manifests agree on {uniq[0]}")
PY
    return $rc
}

self_test() {
    local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/channel-versions.XXXXXX")"
    for p in rust/Cargo.toml rust/rigorix-client/Cargo.toml python/pyproject.toml \
             python/rigorix_verifier/__init__.py typescript/package.json \
             typescript-client/package.json java/pom.xml; do
        mkdir -p "$tmp/$(dirname "$p")"; cp "$ROOT/$p" "$tmp/$p"
    done

    local ok=0 bad=0
    if check "$tmp" >/dev/null 2>&1; then ok=$((ok+1)); else
        echo "❌ self-test: a consistent tree was rejected"; fi

    # Seed the exact drift that shipped: the Java artifact left at an older version.
    python3 - "$tmp/java/pom.xml" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(<artifactId>rigorix-verifier</artifactId>\s*<version>)([^<]+)", r"\g<1>0.2.0", s, count=1)
open(p, "w").write(s)
PY
    if check "$tmp" >/dev/null 2>&1; then
        echo "❌ self-test: a Java version mismatch was accepted"
    else bad=$((bad+1)); fi

    # And the other direction: nothing to compare must not be a pass.
    mkdir -p "$tmp/empty"
    if check "$tmp/empty" >/dev/null 2>&1; then
        echo "❌ self-test: an empty root was accepted"
    else bad=$((bad+1)); fi

    # Third seed, from a real failure: reset the Java drift, then leave an
    # intra-workspace pin behind. `cargo publish` was the only thing that noticed.
    cp "$ROOT/java/pom.xml" "$tmp/java/pom.xml"
    python3 - "$tmp/rust/rigorix-client/Cargo.toml" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'(rigorix-schemas\s*=\s*\{[^}]*?version\s*=\s*"[=^~]?)([0-9][^"]*)', r'\g<1>0.1.0', s, count=1)
open(p, "w").write(s)
PY
    if check "$tmp" >/dev/null 2>&1; then
        echo "❌ self-test: a stale intra-workspace pin was accepted"
    else bad=$((bad+1)); fi

    find "$tmp" -type f -delete 2>/dev/null || true
    find "$tmp" -depth -type d -empty -delete 2>/dev/null || true

    if [ "$ok" -eq 1 ] && [ "$bad" -eq 3 ]; then
        echo "✅ PASS Channel version self-test: consistent accepted, channel drift rejected, stale pin rejected, empty root rejected"
        return 0
    fi
    echo "❌ FAIL Channel version self-test: ok=$ok rejected=$bad (expected ok=1 rejected=3)"
    return 1
}

if [ "$SELF_TEST" -eq 1 ]; then
    self_test
    exit $?
fi

echo "--- Publication channels ---"
check "$ROOT"
