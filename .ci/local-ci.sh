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
#                        [--allow-skips] [--list] [--verify-upstream]
#
# --verify-upstream adds the one step that leaves the machine: it compares the
# vendored artifact to the release asset through the GitHub API (#104). It needs
# `gh` and network, so it is opt-in; without the flag the runner says so instead of
# counting a step that did not run.
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
VERIFY_UPSTREAM=0
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
    --verify-upstream) VERIFY_UPSTREAM=1; shift ;;
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
  run "artifact: the guard can refuse (four planted drifts)" . \
    'bash scripts/check-vendored-artifact.sh --self-test'
  run "artifact: both vendored copies agree" . \
    'bash scripts/check-vendored-artifact.sh'
  if [ "$VERIFY_UPSTREAM" -eq 1 ]; then
    run "artifact: the vendored copy equals the release asset (github api)" . \
      'bash scripts/check-vendored-artifact.sh --verify-upstream'
  fi
  run "repo: no commercial strategy in published files" . \
    'bash .pi/scripts/validate-no-strategy.sh --self-test && bash .pi/scripts/validate-no-strategy.sh'
  run "repo: SPDX on every published source channel" . \
    'bash scripts/check-spdx.sh --self-test && bash scripts/check-spdx.sh'
  run "release: the release checks can refuse (published version, wrong tag, split manifests)" . \
    'bash scripts/check-release.sh --self-test'
  run "release: the runner's tag shape (checkout rewrites refs/tags/<tag>)" . \
    'bash scripts/check-tag-shape.sh'
  run "repo: every workflow file parses (a file GitHub cannot load gates nothing)" . \
    'bash scripts/check-workflows.sh --self-test && bash scripts/check-workflows.sh'
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
  run "audit: exact runtime pins" . 'python3 scripts/check-pins.py --self-test && python3 scripts/check-pins.py'
  run "audit: dependency licences (rust + npm + python)" . \
    'bash scripts/check-licenses.sh --self-test && bash scripts/check-licenses.sh'
  if [ "$PYTHON_LOCAL" -eq 0 ] && command -v docker >/dev/null 2>&1; then
    run "audit: pip-audit --strict (linux docker)" . \
      "docker run --rm -v '$ROOT:/repo' -w /repo/python python:3.12-slim sh -c \"pip install -q --upgrade pip >/dev/null 2>&1; pip install -q pip-audit >/dev/null 2>&1 && bash scripts/audit.sh\""
  else
    run "audit: pip-audit --strict (host)" . \
      'bash python/scripts/audit.sh || { echo "install pip-audit for the host, or run with Docker available"; exit 1; }'
  fi
  # The audit's subject is the dependency graph, not this distribution: `--strict`
  # refuses to audit a package it cannot resolve on PyPI, and the in-tree version is
  # deliberately ahead of the published one (#102). requirements.lock is the same
  # graph the licence audit reads.
  #
  # govulncheck reports the stdlib of the toolchain that *builds*, so the gate is
  # only a property of the tree if the module's floor names a patched release.
  # `go 1.26` did not: it admits 1.26.3, whose stdlib carries 17 advisories, and
  # this step then failed on a host that satisfied the module — a red gate for a
  # machine the tree called in-policy (#98). The floor is now `go 1.26.10`, so a
  # host that can build the module is a host where those advisories are fixed.
  # The toolchain is printed either way, so a failure is attributable.
  run "audit: govulncheck (policy: actionable fails, a later minor is reported)" go '
    python3 ../scripts/govulncheck.py --self-test
    python3 ../scripts/govulncheck.py
  '

  # The seeds. A guard that has never refused anything is a claim, and the
  # workflow that plants these is billing-blocked, so the runner plants them
  # too: a planted range, a planted advisory, a planted vulnerable module. Each
  # mutation happens in a temporary copy — the working tree is never the test
  # subject.
  run "audit: seeds fire (a planted range must fail)" . '
    set -uo pipefail
    seed="$(mktemp -d)"
    mkdir -p "$seed/scripts" "$seed/python/rigorix_verifier/_wasm" "$seed/go/gate/testdata" \
             "$seed/.github/workflows"
    cp .github/workflows/*.yml "$seed/.github/workflows/"
    cp scripts/check-pins.py scripts/check-secrets.sh "$seed/scripts/"
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

    # The surface the guard gained in #105, in a CLEAN second fixture: a tag-pinned
    # action and a tag-pinned scanner must both be refused by name in one run. (A
    # fresh copy, because the range error above would otherwise be the only thing
    # the guard has to report.)
    seed2="$(mktemp -d)"
    mkdir -p "$seed2/scripts" "$seed2/python/rigorix_verifier/_wasm" "$seed2/go/gate/testdata" \
             "$seed2/.github/workflows"
    cp scripts/check-pins.py scripts/check-secrets.sh "$seed2/scripts/"
    cp python/pyproject.toml "$seed2/python/"
    cp go/go.mod "$seed2/go/"
    cp python/rigorix_verifier/_wasm/PROVENANCE.md "$seed2/python/rigorix_verifier/_wasm/"
    cp go/gate/testdata/PROVENANCE.md "$seed2/go/gate/testdata/"
    cp .github/workflows/*.yml "$seed2/.github/workflows/"
    # BSD sed has no `0,/re/` address; one `uses:` per line, so a per-line replace
    # is the same edit.
    sed -i.bak -E "s|uses: actions/checkout@[0-9a-f]{40}.*|uses: actions/checkout@v4|" \
      "$seed2/.github/workflows/ci.yml"
    sed -i.bak -E "s|GITLEAKS_IMAGE:-[^}]+|GITLEAKS_IMAGE:-zricethezav/gitleaks:v8.30.1|" \
      "$seed2/scripts/check-secrets.sh"
    grep -q "uses: actions/checkout@v4" "$seed2/.github/workflows/ci.yml" || { echo "the action plant did not apply"; exit 1; }
    grep -q "gitleaks:v8.30.1}" "$seed2/scripts/check-secrets.sh" || { echo "the scanner plant did not apply"; exit 1; }
    if out2="$(python3 "$seed2/scripts/check-pins.py" 2>&1)"; then
      echo "check-pins.py accepted a tag-pinned action and a tag-pinned scanner; the guard is inert"; exit 1
    fi
    printf "%s\n" "$out2" | grep -q "is not a commit SHA" ||
      { echo "the action plant was not refused by name:"; printf "%s\n" "$out2"; exit 1; }
    printf "%s\n" "$out2" | grep -q "GITLEAKS_IMAGE is zricethezav/gitleaks:v8.30.1" ||
      { echo "the scanner plant was not refused by name:"; printf "%s\n" "$out2"; exit 1; }
    printf "%s\n" "$out2" | head -2
    echo "✅ a planted range, a tag-pinned action and a tag-pinned scanner are refused, each by name"
  '

  if [ "$PYTHON_LOCAL" -eq 0 ] && command -v docker >/dev/null 2>&1; then
    run "audit: seeds fire (a planted advisory must fail)" . \
      "docker run --rm python:3.12-slim sh -c \"pip install -q --upgrade pip >/dev/null 2>&1; pip install -q pip-audit >/dev/null 2>&1; printf 'pyyaml==5.1\\n' > /tmp/planted.txt; if pip-audit --strict -r /tmp/planted.txt >/tmp/o 2>&1; then echo 'pip-audit accepted a known-vulnerable pin; the gate is inert'; exit 1; fi; grep -Eq 'PYSEC-|GHSA-|CVE-' /tmp/o || { echo 'refused for the wrong reason:'; cat /tmp/o; exit 1; }; grep -Eo 'PYSEC-[0-9-]+|GHSA-[a-z0-9-]+' /tmp/o | head -1; echo '✅ a planted advisory is refused, named'\""
  fi

  run "audit: seeds fire (a planted vulnerable module must fail)" . '
    set -uo pipefail
    seed="$(mktemp -d)"
    cp -R go "$seed/go"
    cd "$seed/go"
    [ -f go.mod ] || { echo "the module copy is missing; the seed would prove nothing"; exit 1; }
    go mod edit -require=golang.org/x/text@v0.14.0
    go mod tidy >/dev/null 2>&1 || true
    grep -q "golang.org/x/text v0.14.0" go.mod ||
      { echo "the plant did not take; the seed would prove nothing"; exit 1; }
    # The policy, not the raw tool: a module dependency is fixable here, so it must be
    # refused and the version to name printed (#112).
    set +e
    out="$(python3 "$OLDPWD/scripts/govulncheck.py" --go-dir "$seed/go" --scan-module 2>&1)"
    status=$?
    set -e
    [ "$status" -eq 1 ] ||
      { echo "the policy exited $status, not 1 (actionable) — refused for the wrong reason:"; printf "%s\n" "$out" | head -6; exit 1; }
    printf "%s\n" "$out" | grep -q "golang.org/x/text@v0.14.0" ||
      { echo "the finding did not name the planted module"; printf "%s\n" "$out" | head -6; exit 1; }
    printf "%s\n" "$out" | grep -q "actionable here: fix with" ||
      { echo "the policy did not say it is actionable"; printf "%s\n" "$out" | head -6; exit 1; }
    printf "%s\n" "$out" | grep -E "^❌ GO-" | head -1
    echo "✅ a planted vulnerable module is refused as actionable, naming the module and the fix"
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
  if [ "$VERIFY_UPSTREAM" -eq 0 ]; then
    printf '⏭ the release asset was not compared (pass --verify-upstream: needs gh and network)\n'
  fi
  printf '\nLOCAL CI: GREEN — %d step(s) executed (%s)\n' "$EXECUTED" "$LOG_DIR"
  exit 0
fi
