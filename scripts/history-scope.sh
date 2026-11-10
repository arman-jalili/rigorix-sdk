#!/usr/bin/env bash
# history-scope.sh — where does a name actually appear in what publishing exposes?
#
# `git log --grep` reads commit *messages*; publishing exposes *blobs* as well.
# A decision to accept the history has to state both, per name, with the command
# that produced each cell — otherwise the reader carries away the smaller number.
#
# Usage:
#   bash scripts/history-scope.sh <name> [<name>...]
#   PRIVATE_NAMES="a,b" bash scripts/history-scope.sh
#
# The names are supplied out of band on purpose: the repository states the
# measurement and the method, not the names it is keeping out of the tip.
#
# Columns: tip files | message mentions | revisions whose blobs contain it
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

names=("$@")
if [ "${#names[@]}" -eq 0 ] && [ -n "${PRIVATE_NAMES:-}" ]; then
  IFS=',' read -r -a names <<<"$PRIVATE_NAMES"
fi
if [ "${#names[@]}" -eq 0 ]; then
  cat >&2 <<'USAGE'
usage: bash scripts/history-scope.sh <name> [<name>...]
       PRIVATE_NAMES="name-a,name-b" bash scripts/history-scope.sh

The names are supplied out of band: this script records the method, the
repository does not record the names it keeps out of the tip.
USAGE
  exit 2
fi

printf '%-34s %10s %18s %18s\n' "name (class)" "tip files" "message mentions" "blob revisions"
printf '%-34s %10s %18s %18s\n' "----------------------------------" "----------" "------------------" "------------------"

for name in "${names[@]}"; do
  name="$(printf '%s' "$name" | sed 's/^ *//; s/ *$//')"
  [ -n "$name" ] || continue

  tip="$(git grep -il -- "$name" -- . 2>/dev/null | wc -l | tr -d ' ')"
  messages="$(git log --all --oneline --grep="$name" 2>/dev/null | wc -l | tr -d ' ')"
  # The issue's command: `git grep -il <name> $(git rev-list --all)` deduped by
  # revision, so a name in ten files of one revision counts once.
  blobs="$(
    git grep -il -- "$name" $(git rev-list --all) 2>/dev/null |
      cut -d: -f1 | sort -u | wc -l | tr -d ' '
  )"

  printf '%-34s %10s %18s %18s\n' "$name" "$tip" "$messages" "$blobs"
done

cat <<'NOTE'

Commands, one per column (reproduce a cell by running one):
  tip files        git grep -il -- "<name>" -- . | wc -l
  message mentions git log --all --oneline --grep="<name>" | wc -l
  blob revisions   git grep -il -- "<name>" $(git rev-list --all) | cut -d: -f1 | sort -u | wc -l
NOTE