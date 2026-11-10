#!/usr/bin/env bash
# check-workflows.sh — every workflow file is YAML GitHub can load.
#
# Found while wiring the artifact job (#104): `.github/workflows/audit.yml` had not
# parsed since the govulncheck change, because
#
#     run: "$(go env GOPATH)/bin/govulncheck" ./...
#
# is a quoted scalar followed by junk, not a command. Nothing caught it: Actions
# never loaded the file (billing), no local step parses YAML, and the workflow's
# own text read as if it worked. A workflow that cannot load is not a gate; it is
# a comment with YAML indentation.
#
# Usage:
#   bash scripts/check-workflows.sh             # parse every workflow file
#   bash scripts/check-workflows.sh --self-test # prove an invalid file is refused
#
# Exit: 0 = all parse; 1 = a file does not parse (the parser's message is shown,
# naming file and line); 2 = no YAML parser available or no files found.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF_TEST=0
TREE="$ROOT"

while [ $# -gt 0 ]; do
  case "$1" in
    --self-test) SELF_TEST=1 ;;
    --root) TREE="$2"; shift ;;
    *) echo "check-workflows: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "check-workflows: not verified — python3 has no yaml module (pip install pyyaml)" >&2
  exit 2
fi

parse() {
  local dir="$1" files count=0 file
  files="$(ls "$dir"/.github/workflows/*.yml "$dir"/.github/workflows/*.yaml 2>/dev/null)"
  [ -n "$files" ] || { echo "check-workflows: no subject, not evidence — no workflow file under $dir" >&2; return 2; }
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    count=$((count + 1))
    if ! out="$(python3 -c '
import sys, yaml
try:
    yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
except yaml.YAMLError as error:
    print(f"{sys.argv[1]}: {error}".replace("\n", " "))
    sys.exit(1)
' "$file" 2>&1)"; then
      printf '❌ %s does not parse as YAML — GitHub cannot load it, so it gates nothing\n' "${file#"$dir"/}"
      printf '     %s\n' "$out"
      return 1
    fi
  done < <(printf '%s\n' "$files")
  printf '✅ workflows: %d file(s) parse (a file GitHub cannot load gates nothing)\n' "$count"
  return 0
}

self_test() {
  local tmp failures=0 out
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp' >/dev/null 2>&1 || true" EXIT
  mkdir -p "$tmp/tree/.github/workflows"
  cp "$ROOT"/.github/workflows/*.yml "$tmp/tree/.github/workflows/"

  if out="$(parse "$tmp/tree" 2>&1)"; then
    case "$out" in *"✅ workflows: 3 file(s) parse"*) : ;;
      *) echo "❌ self-test: the real workflows did not parse ($out)"; failures=$((failures + 1)) ;; esac
  else
    echo "❌ self-test: the real workflows failed to parse"; failures=$((failures + 1))
  fi

  # The exact shape that was in audit.yml: a quoted scalar followed by junk.
  printf 'jobs:\n  x:\n    steps:\n      - run: "$(go env GOPATH)/bin/govulncheck" ./...\n' \
    >"$tmp/tree/.github/workflows/planted.yml"
  if out="$(parse "$tmp/tree" 2>&1)"; then
    echo "❌ self-test: a file that cannot load was accepted"; failures=$((failures + 1))
  else
    case "$out" in
      *"does not parse as YAML"*) : ;;
      *) echo "❌ self-test: refused without saying why"; failures=$((failures + 1)) ;;
    esac
    case "$out" in
      *"planted.yml"*) : ;;
      *) echo "❌ self-test: the refusal did not name the file"; failures=$((failures + 1)) ;;
    esac
  fi

  # No files at all is a refusal, not a pass.
  mkdir -p "$tmp/empty/.github/workflows"
  if out="$(parse "$tmp/empty" 2>&1)"; then
    echo "❌ self-test: an empty workflows directory was accepted"; failures=$((failures + 1))
  else
    case "$out" in *"no subject, not evidence"*) : ;;
      *) echo "❌ self-test: empty directory refused without the reason"; failures=$((failures + 1)) ;; esac
  fi

  if [ "$failures" -gt 0 ]; then
    echo "❌ check-workflows self-test: $failures case(s) wrong"
    return 1
  fi
  echo "✅ check-workflows self-test: the real files parse, the unloadable shape is refused by file name, an empty directory refuses"
  return 0
}

if [ "$SELF_TEST" -eq 1 ]; then
  self_test
  exit $?
fi

parse "$TREE"