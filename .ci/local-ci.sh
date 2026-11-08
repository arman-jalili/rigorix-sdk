#!/usr/bin/env bash
# local-ci.sh — run every CI job on this machine when GitHub Actions minutes are gone.
#
# Mirrors .github/workflows/ci.yml:
#   verifier (rust), python-verifier, typescript-verifier, typescript-client,
#   go-verifier-client, java-verifier, publish-helper
# then the pre-MR .pi validators.
#
# The Python job runs in `python:3.12-slim` when Docker is available, because
# wasmtime's JIT is SIGKILLed by this macOS sandbox; the container matches the
# ubuntu-latest CI. Use --python-local to force the host interpreter (the
# binding tests then skip on Darwin, as they do under pytest).
#
# Usage:
#   bash .ci/local-ci.sh [--jobs-only | --validators-only] [--python-local]
#
# Exit: 0 = every step green; 1 = at least one failed (logs are printed and kept).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOCAL_CI_LOG_DIR:-$(mktemp -d)}"
MODE="all"
PYTHON_LOCAL=0
FAILED=0

while [ $# -gt 0 ]; do
  case "$1" in
    --jobs-only) MODE="jobs"; shift ;;
    --validators-only) MODE="validators"; shift ;;
    --python-local) PYTHON_LOCAL=1; shift ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "local-ci: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

run() {
  local name="$1" dir="$2" cmd="$3"
  local slug log start
  slug="$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')"
  log="$LOG_DIR/$slug.log"
  start="$(date +%s)"
  printf '\n▶ %s\n' "$name"
  if ( cd "$ROOT/$dir" && bash -c "$cmd" ) >"$log" 2>&1; then
    printf '✅ %s (%ss)\n' "$name" "$(( $(date +%s) - start ))"
  else
    printf '❌ %s (%ss) — %s\n' "$name" "$(( $(date +%s) - start ))" "$log"
    tail -n 50 "$log" | sed 's/^/   /'
    FAILED=1
  fi
}

job_rust() {
  run "rust: publication channels agree" . \
    'bash .pi/scripts/validate-channel-versions.sh && bash .pi/scripts/validate-channel-versions.sh --self-test'
  run "rust: fmt" rust 'cargo fmt --check'
  run "rust: clippy" rust 'cargo clippy --all-targets -- -D warnings'
  run "rust: test --workspace" rust 'cargo test --workspace'
  run "rust: package rigorix-schemas" rust 'cargo package -p rigorix-schemas'
  run "rust: packaged-crate smoke" rust './scripts/verify-packaged-crates.sh'
  run "rust: verifier self-containment" rust \
    'unset RIGORIX_SDK_SCHEMAS; cargo test -p rigorix-verifier --lib'
  run "rust: no rigorix-engine dependency" rust \
    'if cargo tree -p rigorix-client | grep -q rigorix-engine; then echo "rigorix-client must not depend on rigorix-engine"; exit 1; fi'
}

job_python() {
  if [ "$PYTHON_LOCAL" -eq 0 ] && command -v docker >/dev/null 2>&1; then
    local job="$LOG_DIR/python-job.sh"
    cat >"$job" <<'PY'
set -euo pipefail
pip install -q --upgrade pip build
pip install -q -e ".[test]"
pytest -q
dist="$(mktemp -d)"
wheel="$(mktemp -d)"
sdist="$(mktemp -d)"
python -m build --outdir "$dist"
python -m venv "$wheel"
"$wheel/bin/pip" install -q "$dist"/*.whl
RIGORIX_SDK_SCHEMAS= "$wheel/bin/python" scripts/pack_smoke.py
python -m venv "$sdist"
"$sdist/bin/pip" install -q "$dist"/*.tar.gz
RIGORIX_SDK_SCHEMAS= "$sdist/bin/python" scripts/pack_smoke.py
PY
    run "python: pytest + wheel/sdist smoke (linux docker)" . \
      "docker run --rm -v '$ROOT:/repo' -v '$job:/tmp/job.sh:ro' -w /repo/python python:3.12-slim sh /tmp/job.sh"
  else
    run "python: pytest (host; binding tests skip on Darwin)" python 'pytest -q'
    local tmp; tmp="$(mktemp -d)"
    run "python: wheel/sdist smoke (host)" python "
      set -euo pipefail
      python -m build --outdir '$tmp' >/dev/null
      python -m venv '$tmp/wheel'
      '$tmp/wheel/bin/pip' install -q '$tmp'/*.whl
      RIGORIX_SDK_SCHEMAS= '$tmp/wheel/bin/python' scripts/pack_smoke.py
    "
  fi
}

job_typescript_verifier() {
  run "ts-verifier: npm ci" typescript 'npm ci'
  run "ts-verifier: test" typescript 'npm test'
  run "ts-verifier: browser conformance" typescript 'npm run test:browser'
  local tmp; tmp="$(mktemp -d)"
  run "ts-verifier: pack smoke" typescript "
    set -euo pipefail
    npm run build
    npm pack --pack-destination '$tmp'
    TARBALL=\$(ls '$tmp'/rigorix-verifier-*.tgz | head -1)
    WORK='$tmp/smoke'
    mkdir -p \"\$WORK\"
    cp scripts/pack-smoke.mjs \"\$WORK/smoke.mjs\"
    cd \"\$WORK\"
    npm init -y >/dev/null
    npm install \"\$TARBALL\" --no-audit --no-fund >/dev/null
    unset RIGORIX_SDK_SCHEMAS
    node smoke.mjs
  "
}

job_typescript_client() {
  run "ts-client: npm ci" typescript-client 'npm ci'
  run "ts-client: test" typescript-client 'npm test'
}

job_go() {
  run "go: corpus is regenerated" go \
    'go generate ./... && git diff --exit-code -- internal/corpus/corpus_gen.go'
  run "go: vet" go 'go vet ./...'
  run "go: test" go 'go test ./...'
  run "go: gate pure Go (CGO_ENABLED=0)" go 'CGO_ENABLED=0 go test ./gate/...'
}

job_java() {
  run "java: mvn verify" java 'mvn -B -q verify'
}

job_publish_helper() {
  run "publish-helper: syntax + classification" . '
    set -eu
    helper=.github/scripts/wait-for-registry.sh
    bash -n "$helper"
    expect() {
      want="$1"; shift
      set +e
      "$@" >/tmp/helper.out 2>&1
      got=$?
      set -e
      if [ "$got" -ne "$want" ]; then
        echo "expected exit $want, got $got"; cat /tmp/helper.out; exit 1
      fi
      echo "✅ exit $got (expected $want)"
    }
    expect 0 "$helper" npm bash -c "exit 0"
    expect 2 "$helper" npm bash -c "echo \"npm ERR! code EINTEGRITY\"; exit 1"
    expect 3 env REGISTRY_MAX_ATTEMPTS=1 REGISTRY_RETRY_SECONDS=0 \
      "$helper" pypi bash -c "echo \"No matching distribution found\"; exit 1"
    counter="$(mktemp)"
    echo 0 > "$counter"
    expect 0 env COUNTER="$counter" REGISTRY_MAX_ATTEMPTS=3 REGISTRY_RETRY_SECONDS=0 \
      "$helper" npm bash -c "n=\$(cat \"\$COUNTER\"); n=\$((n+1)); echo \"\$n\" > \"\$COUNTER\"; [ \"\$n\" -ge 2 ] || { echo ETARGET; exit 1; }"
  '
}

job_validators() {
  for script in validate-ci validate-tests validate-security validate-operations \
    validate-canonical validate-architecture validate-integration; do
    run "validator: $script" . "bash .pi/scripts/$script.sh"
  done
}

echo "local-ci: repo=$ROOT logs=$LOG_DIR mode=$MODE"

if [ "$MODE" != "validators" ]; then
  job_rust
  job_python
  job_typescript_verifier
  job_typescript_client
  job_go
  job_java
  job_publish_helper
fi

if [ "$MODE" != "jobs" ]; then
  job_validators
fi

if [ "$FAILED" -eq 0 ]; then
  printf '\nLOCAL CI: GREEN (%s)\n' "$LOG_DIR"
else
  printf '\nLOCAL CI: RED — inspect %s\n' "$LOG_DIR"
fi
exit "$FAILED"
