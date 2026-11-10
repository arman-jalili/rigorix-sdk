#!/usr/bin/env bash
# audit.sh — `pip-audit --strict` over the locked dependency graph, with one retry
# for a resolver bootstrap failure and never for a finding.
#
# Two things this encodes, both learned the hard way:
#
# 1. The subject is requirements.lock, not the installed distribution. `--strict`
#    refuses to audit a package it cannot resolve on PyPI, and the in-tree version is
#    deliberately ahead of the published one (#102) — auditing `-e .` reported
#    "Dependency not found on PyPI and could not be audited: rigorix-verifier
#    (0.10.0)", which is a fact about the release, not an advisory. The lock is the
#    same graph the licence audit reads, so both gates audit one list.
#
# 2. `pip-audit -r` builds its own resolver environment, and that bootstrap fails
#    transiently ("Failed to upgrade `pip`"). Retrying a *network* failure is honest;
#    retrying a *finding* would be the gate lying. So the retry matches the
#    bootstrap's own words, and a finding exits 1 on the first attempt.
#
# Usage: bash python/scripts/audit.sh
# Exit: 0 = no known vulnerabilities; 1 = a finding, or two bootstrap failures;
#       2 = pip-audit is not installed.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

command -v pip-audit >/dev/null 2>&1 || {
  echo "audit: pip-audit is not installed (pip install pip-audit)" >&2
  exit 2
}

attempt=1
while [ "$attempt" -le 2 ]; do
  if out="$(pip-audit --strict -r requirements.lock 2>&1)"; then
    printf '%s\n' "$out"
    exit 0
  fi
  printf '%s\n' "$out" >&2
  # The resolver's own failure, not ours: the venv it builds to read the lock.
  if printf '%s' "$out" | grep -qE 'Failed to upgrade|Failed to resolve|Could not find a version|Temporary failure in name resolution'; then
    if [ "$attempt" -eq 1 ]; then
      echo "⚠ pip-audit could not build its resolver environment; retrying once (network, not a finding)" >&2
      attempt=$((attempt + 1))
      continue
    fi
  fi
  exit 1
done
exit 1