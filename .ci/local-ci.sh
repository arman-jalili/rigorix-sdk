#!/usr/bin/env bash
# local-ci.sh — run every CI job on this machine when GitHub Actions minutes are gone.
#
# Mirrors .github/workflows/ci.yml:
#   verifier (rust), python-verifier, typescript-verifier, typescript-client,
#   go-verifier-client, java-verifier, publish-helper
# plus .github/workflows/audit.yml (runtime pins, pip-audit, govulncheck),
# then the pre-MR .pi validators.
#
# The Python job runs in `python:3.12-slim` when Docker is available, because
# wasmtime's JIT is SIGKILLed by this macOS sandbox; the container matches the
# ubuntu-latest CI. Use --python-local to force the host interpreter (the
# binding tests then skip on Darwin, as they do under pytest).
#
# A step that executed no tests is not a green step (#73): the Python binding
# suite skips itself on Darwin without Docker, and reporting that as "✅" made
# this runner the only verdict available while it proved nothing. The binding
# suite therefore runs as its OWN step (a whole-suite check never fires, because
# the other Python tests still pass), and a step whose summary says `N skipped`
# and nothing else fails, naming the suite. Use --allow-skips to run anyway: the
# step is then listed as SKIPPED, never ✅.
#
# Usage:
#   bash .ci/local-ci.sh [--jobs-only | --validators-only] [--python-local]
#                        [--allow-skips] [--list]
#
# --list prints every step the runner can execute, including both sides of a
# branch (docker/host, python-local). It is a list of call sites, not of a run:
# only one side of each branch executes on a given machine.
#
# Exit: 0 = every step green and every step had a subject
#       1 = at least one step failed (logs are printed and kept)
#       3 = green, but at least one step was skipped (--allow-skips); not full
#           evidence, and a caller checking `-eq 0` will see the difference.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOCAL_CI_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$LOG_DIR"
MODE="all"
PYTHON_LOCAL=0
ALLOW_SKIPS=0
FAILED=0
EXECUTED=0
FAILED_COUNT=0
SKIPPED_COUNT=0
SKIPPED_STEPS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --jobs-only) MODE="jobs"; shift ;;
    --validators-only) MODE="validators"; shift ;;
    --python-local) PYTHON_LOCAL=1; shift ;;
    --allow-skips) ALLOW_SKIPS=1; shift ;;
    --list) MODE="list"; shift ;;
    -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "local-ci: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

# pytest_summary <log> — "passed failed skipped errors" from the last summary
# line, or nothing when pytest printed none (a collection error exits non-zero
# anyway, so the caller's failure branch handles it).
pytest_summary() {
  local line
  line="$(grep -E '[0-9]+ (passed|failed|skipped|error|errors)' "$1" |
    grep -E ' in [0-9.]+s' | tail -1)"
  [ -n "$line" ] || return 0
  local passed failed skipped errors
  passed="$(printf '%s' "$line" | grep -Eo '[0-9]+ passed' | grep -Eo '[0-9]+' | head -1)"
  failed="$(printf '%s' "$line" | grep -Eo '[0-9]+ failed' | grep -Eo '[0-9]+' | head -1)"
  errors="$(printf '%s' "$line" | grep -Eo '[0-9]+ errors?' | grep -Eo '[0-9]+' | head -1)"
  skipped="$(printf '%s' "$line" | grep -Eo '[0-9]+ skipped' | grep -Eo '[0-9]+' | head -1)"
  printf '%s %s %s %s\n' "${passed:-0}" "${failed:-0}" "${skipped:-0}" "${errors:-0}"
}

run() {
  local name="$1" dir="$2" cmd="$3" subject="${4:-}"
  local slug log start
  slug="$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')"
  log="$LOG_DIR/$slug.log"
  start="$(date +%s)"
  printf '\n▶ %s\n' "$name"
  if ( cd "$ROOT/$dir" && bash -c "$cmd" ) >"$log" 2>&1; then
    local elapsed detail=""
    elapsed="$(( $(date +%s) - start ))"
    if [ "$subject" = "pytest" ]; then
      local passed=0 failed=0 skipped=0 errors=0
      read -r passed failed skipped errors <<<"$(pytest_summary "$log")" || true
      detail=" — ${passed:-0} passed, ${skipped:-0} skipped"
      if [ "${passed:-0}" -eq 0 ] && [ "${failed:-0}" -eq 0 ] &&
        [ "${errors:-0}" -eq 0 ] && [ "${skipped:-0}" -gt 0 ]; then
        if [ "$ALLOW_SKIPS" -eq 1 ]; then
          printf '⏭ %s (%ss) — SKIPPED: %s test(s), 0 executed (--allow-skips)\n' \
            "$name" "$elapsed" "$skipped"
          SKIPPED_STEPS="$SKIPPED_STEPS
  - $name"
          SKIPPED_COUNT=$(( SKIPPED_COUNT + 1 ))
          return 0
        fi
        printf '❌ %s (%ss) — the suite executed 0 tests (%s skipped); %s\n' \
          "$name" "$elapsed" "$skipped" "$log"
        grep -E '^SKIPPED' "$log" | head -3 | sed 's/^/   /'
        FAILED=1
        FAILED_COUNT=$(( FAILED_COUNT + 1 ))
        return 0
      fi
    fi
    EXECUTED=$(( EXECUTED + 1 ))
    printf '✅ %s%s (%ss)\n' "$name" "$detail" "$elapsed"
  else
    printf '❌ %s (%ss) — %s\n' "$name" "$(( $(date +%s) - start ))" "$log"
    tail -n 50 "$log" | sed 's/^/   /'
    FAILED=1
    FAILED_COUNT=$(( FAILED_COUNT + 1 ))
  fi
}

job_rust() {
  run "artifact: both vendored copies agree" . \
    'bash scripts/check-vendored-artifact.sh'
  run "repo: no commercial strategy in published files" . \
    'bash .pi/scripts/validate-no-strategy.sh --self-test && bash .pi/scripts/validate-no-strategy.sh'
  run "repo: SPDX on every published source channel" . \
    'bash scripts/check-spdx.sh --self-test && bash scripts/check-spdx.sh'
  run "repo: documents state the agreement in use (CLA, not DCO)" . \
    'bash scripts/check-agreement.sh --self-test && bash scripts/check-agreement.sh'
  run "repo: no credential in the history (gitleaks)" . \
    'bash scripts/check-secrets.sh --self-test && bash scripts/check-secrets.sh'
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
pytest -q -rs
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
      "docker run --rm -v '$ROOT:/repo' -v '$job:/tmp/job.sh:ro' -w /repo/python python:3.12-slim sh /tmp/job.sh" pytest
  else
    run "python: pytest (host; every suite but the binding)" python \
      'pytest -q -rs --ignore=tests/binding_test.py' pytest
    # Separate subject: on Darwin this is 14 skips and zero tests, which is not
    # evidence that the binding works. The step name says which suite is silent.
    run "python: binding suite (needs a working wasmtime JIT)" python \
      'pytest -q -rs tests/binding_test.py' pytest
    local tmp; tmp="$(mktemp -d)"
    # Self-contained: the host interpreter may have no `build`, and macOS's
    # system python3 cannot install into it. A venv carries the builder.
    run "python: wheel/sdist smoke (host)" python "
      set -euo pipefail
      python3 -m venv '$tmp/buildenv'
      '$tmp/buildenv/bin/pip' install -q build
      '$tmp/buildenv/bin/python' -m build --outdir '$tmp/dist' >/dev/null
      python3 -m venv '$tmp/wheel'
      '$tmp/wheel/bin/pip' install -q '$tmp/dist'/*.whl
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

job_audit() {
  # Mirrors .github/workflows/audit.yml (SDL-5): the two runtimes the gate now
  # depends on are pinned exactly and scanned for known advisories. This is not
  # in ci.yml because advisories are published after a merge, not before it.
  run "audit: exact runtime pins" . 'python3 scripts/check-pins.py'
  run "audit: dependency licences (rust + npm + python)" . \
    'bash scripts/check-licenses.sh --self-test && bash scripts/check-licenses.sh'
  if [ "$PYTHON_LOCAL" -eq 0 ] && command -v docker >/dev/null 2>&1; then
    run "audit: pip-audit --strict (linux docker)" . \
      "docker run --rm -v '$ROOT:/repo' -w /repo/python python:3.12-slim sh -c \"pip install -q --upgrade pip >/dev/null 2>&1; pip install -q -e '.[test]' pip-audit >/dev/null 2>&1 && pip-audit --strict\""
  else
    run "audit: pip-audit --strict (host)" . \
      'python3 -m pip_audit --strict || { echo "install pip-audit for the host, or run with Docker available"; exit 1; }'
  fi
  # govulncheck reports the stdlib of the toolchain that *builds*, so the gate is
  # only a property of the tree if the module's floor names a patched release.
  # `go 1.26` did not: it admits 1.26.3, whose stdlib carries 17 advisories, and
  # this step then failed on a host that satisfied the module — a red gate for a
  # machine the tree called in-policy (#98). The floor is now `go 1.26.10`, so a
  # host that can build the module is a host where those advisories are fixed.
  # The toolchain is printed either way, so a failure is attributable.
  run "audit: govulncheck (toolchain printed)" go '
    set -uo pipefail
    echo "toolchain: $(go version)"
    go install golang.org/x/vuln/cmd/govulncheck@latest >/dev/null 2>&1
    if ! "$(go env GOPATH)/bin/govulncheck" ./...; then
      echo "called vulnerabilities found — the gate fails"
      exit 1
    fi
    # Advisories the code does not reach are printed, not silently passed.
    echo "--- module scope (informational: advisories the code does not call) ---"
    "$(go env GOPATH)/bin/govulncheck" -scan=module || true
  '

  # The seeds. A guard that has never refused anything is a claim, and the
  # workflow that plants these is billing-blocked, so the runner plants them
  # too: a planted range, a planted advisory, a planted vulnerable module. Each
  # mutation happens in a temporary copy — the working tree is never the test
  # subject.
  run "audit: seeds fire (a planted range must fail)" . '
    set -uo pipefail
    seed="$(mktemp -d)"
    mkdir -p "$seed/scripts" "$seed/python/rigorix_verifier/_wasm" "$seed/go/gate/testdata"
    cp scripts/check-pins.py "$seed/scripts/"
    cp python/pyproject.toml "$seed/python/"
    cp go/go.mod "$seed/go/"
    cp python/rigorix_verifier/_wasm/PROVENANCE.md "$seed/python/rigorix_verifier/_wasm/"
    cp go/gate/testdata/PROVENANCE.md "$seed/go/gate/testdata/"
    sed -i.bak "s/\"wasmtime==[0-9.]*\"/\"wasmtime>=20.0\"/" "$seed/python/pyproject.toml"
    if out="$(python3 "$seed/scripts/check-pins.py" 2>&1)"; then
      echo "check-pins.py accepted a range; the guard is inert"; exit 1
    fi
    # A seed fails for a reason, not just with a status: the reason must be the
    # planted one. A missing ROOT would also exit 1, and would prove nothing.
    printf "%s\n" "$out" | grep -q "must be pinned exactly" ||
      { echo "refused for the wrong reason:"; printf "%s\n" "$out"; exit 1; }
    printf "%s\n" "$out" | head -1
    echo "✅ a planted range is refused, naming the range"
  '

  if [ "$PYTHON_LOCAL" -eq 0 ] && command -v docker >/dev/null 2>&1; then
    run "audit: seeds fire (a planted advisory must fail)" . \
      "docker run --rm python:3.12-slim sh -c \"pip install -q --upgrade pip >/dev/null 2>&1; pip install -q pip-audit >/dev/null 2>&1; printf 'pyyaml==5.1\\n' > /tmp/planted.txt; if pip-audit --strict -r /tmp/planted.txt >/tmp/o 2>&1; then echo 'pip-audit accepted a known-vulnerable pin; the gate is inert'; exit 1; fi; grep -Eq 'PYSEC-|GHSA-|CVE-' /tmp/o || { echo 'refused for the wrong reason:'; cat /tmp/o; exit 1; }; grep -Eo 'PYSEC-[0-9-]+|GHSA-[a-z0-9-]+' /tmp/o | head -1; echo '✅ a planted advisory is refused, named'\""
  fi

  run "audit: seeds fire (a planted vulnerable module must fail)" . '
    set -uo pipefail
    seed="$(mktemp -d)"
    cp -R go "$seed/go"
    cp go/go.mod "$seed/go.orig"
    cp go/go.sum "$seed/go.sum.orig"
    cd "$seed/go"
    [ -f go.mod ] || { echo "the module copy is missing; the seed would prove nothing"; exit 1; }
    go mod edit -require=golang.org/x/text@v0.14.0
    go mod tidy >/dev/null 2>&1 || true
    grep -q "golang.org/x/text v0.14.0" go.mod ||
      { echo "the plant did not take; the seed would prove nothing"; exit 1; }
    set +e
    out="$("$(go env GOPATH)/bin/govulncheck" -scan=module 2>&1)"
    status=$?
    set -e
    [ "$status" -eq 3 ] ||
      { echo "govulncheck exited $status, not 3 (findings) — refused for the wrong reason:"; printf "%s\n" "$out" | head -5; exit 1; }
    printf "%s\n" "$out" | grep -q "golang.org/x/text@v0.14.0" ||
      { echo "findings did not name the planted module"; printf "%s\n" "$out" | head -5; exit 1; }
    printf "%s\n" "$out" | grep -E "^Vulnerability #" | head -1
    echo "✅ a planted vulnerable module is refused, named"
  '
}

job_validators() {
  for script in validate-ci validate-tests validate-security validate-operations \
    validate-canonical validate-architecture validate-integration \
    validate-no-strategy; do
    run "validator: $script" . "bash .pi/scripts/$script.sh"
  done
}

if [ "$MODE" = "list" ]; then
  # Call sites, in script order. A branch (docker vs host) contributes both; the
  # count of an actual run is printed by the verdict line instead.
  grep -oE 'run "[^"]+"' "$0" |
    sed 's/^run "//; s/"$//' |
    awk '{ printf "%2d. %s\n", NR, $0 }'
  exit 0
fi

echo "local-ci: repo=$ROOT logs=$LOG_DIR mode=$MODE"

if [ "$MODE" != "validators" ]; then
  job_rust
  job_python
  job_typescript_verifier
  job_typescript_client
  job_go
  job_java
  job_publish_helper
  job_audit
fi

if [ "$MODE" != "jobs" ]; then
  job_validators
fi

if [ "$FAILED" -ne 0 ]; then
  # The count is printed, never typed into a report: a hand-written step count
  # is a claim about the script that the script itself can derive.
  printf '\nLOCAL CI: RED — %d step(s) executed, %d failed (%s)\n' \
    "$EXECUTED" "$FAILED_COUNT" "$LOG_DIR"
  exit 1
elif [ "$SKIPPED_COUNT" -gt 0 ]; then
  printf '\nLOCAL CI: GREEN EXCEPT SKIPPED STEPS (not full evidence):%s\n' "$SKIPPED_STEPS"
  printf '  %d step(s) executed, %d skipped; a skip is a decision, not a pass\n  logs: %s\n' \
    "$EXECUTED" "$SKIPPED_COUNT" "$LOG_DIR"
  exit 3
else
  printf '\nLOCAL CI: GREEN — %d step(s) executed (%s)\n' "$EXECUTED" "$LOG_DIR"
  exit 0
fi
