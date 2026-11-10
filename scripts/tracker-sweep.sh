#!/usr/bin/env bash
# tracker-sweep.sh — issue and pull-request bodies are published documents (#89).
#
# A body is not a private note: it becomes public with the repository and it is
# indexed. The tree has a guard for what it publishes (validate-no-strategy.sh);
# the tracker had none, because `git grep` cannot see it.
#
# Names are supplied out of band, like scripts/history-scope.sh: the repository
# records the method, not the names it is keeping out of the published record.
#
# Usage:
#   PRIVATE_NAMES="name-a,name-b" bash scripts/tracker-sweep.sh
#
# Exit: 0 = no hit; 1 = at least one item names a private repository or carries
# commercial vocabulary (item number, class and the matched fragment printed).
set -uo pipefail

command -v gh >/dev/null 2>&1 || { echo "tracker-sweep: gh is required" >&2; exit 2; }

names="${PRIVATE_NAMES:-}"
if [ -z "$names" ]; then
  cat >&2 <<'USAGE'
usage: PRIVATE_NAMES="name-a,name-b" bash scripts/tracker-sweep.sh

The names are supplied out of band: this script records the method, the
repository does not record the names it keeps out of the published tracker.
USAGE
  exit 2
fi

# Scanned surface: title and body. A title is a published document too.
#
# Class 1: a private repository name (from PRIVATE_NAMES).
# Class 2: commercial vocabulary that belongs in a plan, not a published body.
# Class 3: an internal hostname.
pattern="$(printf '%s' "$names" | sed 's/,/|/g')"
commercial='\bfunnel\b|go-to-market|\bGTM\b|\bpricing\b|\bcompetitor\b|\bbuyers?\b'
host='[a-z0-9-]+\.internal\b'

tmp="$(mktemp -d)"
trap 'rm -f "$tmp"/*.json' EXIT
gh issue list --state all --limit 500 --json number,title,body >"$tmp/issues.json" || exit 2
gh pr list --state all --limit 500 --json number,title,body >"$tmp/prs.json" || exit 2

python3 - "$tmp/issues.json" "$tmp/prs.json" "$pattern" "$commercial" "$host" <<'PY'
import json, re, sys

issues_path, prs_path, names, commercial, host = sys.argv[1:6]
classes = (("private-repository", names), ("commercial", commercial), ("internal-host", host))
found = 0
for kind, path in (("issue", issues_path), ("pr", prs_path)):
    for item in json.load(open(path)):
        body = f"{item.get('title') or ''}\n{item.get('body') or ''}"
        hits = []
        for label, pattern in classes:
            match = re.search(pattern, body, re.I)
            if match:
                fragment = " ".join(body[max(0, match.start() - 40):match.end() + 40].split())
                hits.append(f"{label}: …{fragment}…")
        if hits:
            found += 1
            print(f"{kind} #{item['number']}  {item['title'][:60]}")
            for hit in hits:
                print(f"    {hit}")
print(("✅ tracker: no private name, commercial vocabulary or internal host in any "
       f"{'body' if not found else 'unresolved body'}" if not found else
       f"❌ tracker: {found} item(s) with a hit"))
sys.exit(0 if not found else 1)
PY
