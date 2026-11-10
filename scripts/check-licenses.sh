#!/usr/bin/env bash
# check-licenses.sh — the dependency licence gate (#86).
#
# The repository is Apache-2.0. Its dependencies are not vendored, but they are
# linked, and an obligation travels with the binary. Nothing here ran a licence
# check before this script, so the statement "Apache-2.0" was a claim about the
# tree and an assumption about the graph.
#
# Three ecosystems, three tools, one policy:
#   Rust   cargo deny check licenses   (rust/deny.toml is the policy)
#   npm    license-checker             (both packages, against their lockfiles)
#   Python pip-licenses                (against the committed requirements.lock,
#                                       so the audited graph is the shipped one)
#
# The Python gate uses `--partial-match`: without it `--fail-on GPL` compares
# whole strings and `GPL-2.0-or-later` slips through — a gate that never fires.
#
# Usage:
#   bash scripts/check-licenses.sh               # the three gates
#   bash scripts/check-licenses.sh --self-test   # planted GPL in each ecosystem
#
# Exit: 0 = every graph is within policy; 1 = a rejected licence (named);
#       2 = a tool is unavailable (not a pass).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# An allow-list, not a deny-list: license-checker's --failOn compares whole
# strings, so `--failOn GPL` never matches `GPL-3.0` — a gate that cannot fire.
# The allow-list fails on anything unrecognised, which is the policy.
NPM_ALLOW='MIT;Apache-2.0;BSD-2-Clause;BSD-3-Clause;ISC;0BSD;Unlicense;CC0-1.0'
DENY_LIST='GPL;AGPL;SSPL;CDDL;EPL'
# pip-licenses matches substrings only with --partial-match; the list above is a
# prefix list, not exact licence names.
PIP_DENY='GPL;AGPL;SSPL'

cargo_gate() {
  ( cd "$ROOT/rust" && cargo deny check licenses )
}

npm_gate() {
  local dir="$1"
  ( cd "$dir" && npx --yes license-checker@25 --summary --onlyAllow "$NPM_ALLOW" )
}

# pip_gate [extra pip package ...] — the extras exist for the seed.
pip_gate() {
  local extra="${*:-}"
  docker run --rm -v "$ROOT/python:/repo" -w /repo python:3.12-slim sh -c \
    "pip install -q -r requirements.lock pip-licenses $extra >/dev/null 2>&1 &&
     pip-licenses --partial-match --fail-on '$PIP_DENY'"
}

self_test() {
  local failed=0 tmp saved

  echo "▶ seed: a GPL expression in the Rust workspace"
  saved="$(mktemp)"
  cp "$ROOT/rust/Cargo.toml" "$saved"
  # shellcheck disable=SC2064
  trap "cp '$saved' '$ROOT/rust/Cargo.toml'" RETURN
  sed -i.bak 's/^license = "Apache-2.0"/license = "GPL-3.0"/' "$ROOT/rust/Cargo.toml"
  if cargo_gate >/dev/null 2>&1; then
    echo "❌ rust seed: cargo deny accepted a GPL workspace licence"
    failed=1
  else
    echo "✅ rust seed: cargo deny refused GPL-3.0"
  fi
  cp "$saved" "$ROOT/rust/Cargo.toml"
  trap - RETURN

  echo "▶ seed: a GPL package in an npm tree (planted, no network)"
  tmp="$(mktemp -d)"
  printf '{"name":"planted","version":"1.0.0","dependencies":{"gpl-planted":"1.0.0"}}\n' \
    >"$tmp/package.json"
  mkdir -p "$tmp/node_modules/gpl-planted"
  printf '{"name":"gpl-planted","version":"1.0.0","license":"GPL-3.0"}\n' \
    >"$tmp/node_modules/gpl-planted/package.json"
  if npm_gate "$tmp" >/dev/null 2>&1; then
    echo "❌ npm seed: license-checker accepted a GPL-3.0 dependency"
    failed=1
  else
    echo "✅ npm seed: license-checker refused GPL-3.0"
  fi

  echo "▶ seed: a GPL package in the Python environment"
  if ! command -v docker >/dev/null 2>&1; then
    echo "⏭ python seed needs docker"
    return 2
  fi
  if pip_gate "pylint" >/dev/null 2>&1; then
    echo "❌ python seed: pip-licenses accepted GPL-2.0-or-later"
    failed=1
  else
    echo "✅ python seed: pip-licenses refused GPL-2.0-or-later"
  fi

  if [ "$failed" -ne 0 ]; then
    echo "❌ licence-gate self-test failed — a gate is inert"
    return 1
  fi
  echo "✅ licence-gate self-test: each ecosystem refuses a planted GPL"
  return 0
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

status=0

echo "▶ Rust (rust/deny.toml)"
if cargo_gate; then
  echo "✅ rust: the graph is within policy"
else
  echo "❌ rust: a dependency licence is not allowed by rust/deny.toml"
  status=1
fi

for dir in typescript typescript-client; do
  echo "▶ npm ($dir)"
  if [ ! -d "$ROOT/$dir/node_modules" ]; then
    echo "⏭ $dir/node_modules is absent — run npm ci first; not a pass" >&2
    status=2
    continue
  fi
  if npm_gate "$ROOT/$dir"; then
    echo "✅ npm ($dir): the lockfile graph is within policy"
  else
    echo "❌ npm ($dir): a dependency licence is on the deny list"
    status=1
  fi
done

echo "▶ Python (python/requirements.lock)"
if ! command -v docker >/dev/null 2>&1; then
  echo "⏭ python gate needs docker; not a pass" >&2
  status=2
else
  if pip_gate; then
    echo "✅ python: the lockfile graph is within policy"
  else
    echo "❌ python: a dependency licence is on the deny list"
    status=1
  fi
fi

if [ "$status" -eq 0 ]; then
  echo "✅ licence gate: rust + npm ×2 + python within policy (deny: $DENY_LIST)"
fi
exit "$status"