#!/usr/bin/env bash
# walk-release.sh — execute RELEASING.md §Order, offline, and prove the order is the one
# the gate permits (#136).
#
# This is the walk-through that produced #133's acceptance evidence — and, in its first
# life, the harness that pushed three tags into this repository, because it left the
# clone's `origin` pointing at the subject. Two consequences, both fixed here:
#
#   * it lives in the tree, so `#133`'s criterion is reproducible rather than a transcript;
#   * it **cannot** reach the subject: the clone's origin is a scratch bare repository in
#     the run's temp dir, and a trap compares this repository's own tags — locally, and on
#     the real remote when it is reachable — before and after, on success and on failure.
#
# The order it walks is the six steps of RELEASING.md §Order, each followed by the gate
# that enforces it. `--order crates-first` walks the *old* order instead, which the same
# gate refuses: that is the test for the runbook's reversal.
#
# Usage:
#   bash scripts/walk-release.sh                       # the next version, all six steps
#   bash scripts/walk-release.sh --version 0.11.0
#   bash scripts/walk-release.sh --order crates-first  # exit 1, naming the refusal
#   bash scripts/walk-release.sh --order crates-first --expect-refusal
#                                                      # exit 0 when the refusal is the
#                                                      # expected outcome (for CI)
#
# Exit: 0 = every step behaved as RELEASING.md says (or, with --expect-refusal, the old
#       order was refused naming the channel); 1 = a step disagreed; 2 = environment.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/scripts/check-release.sh"
ORDER="permitted"
EXPECT_REFUSAL=0
VERSION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --order) ORDER="$2"; shift ;;
    --expect-refusal) EXPECT_REFUSAL=1 ;;
    *) echo "walk-release: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

case "$ORDER" in
  permitted|crates-first) ;;
  *) echo "walk-release: --order must be 'permitted' or 'crates-first', not '$ORDER'" >&2; exit 2 ;;
esac

# Invoked through `bash`: this repository's scripts are not executable bits in git.
[ -f "$GATE" ] || { echo "walk-release: no check-release.sh at $GATE" >&2; exit 2; }

failures=0
step() { printf '\n▶ %s\n' "$*"; }
say() { printf '   %s\n' "$*"; }
run() {  # run COMMAND… — print it, then its output indented
  printf '   $ %s\n' "$*"
  "$@" 2>&1 | sed 's/^/     /'
  return "${PIPESTATUS[0]}"
}

# ── the version under test ──────────────────────────────────────────────────────────
CURRENT="$(bash "$GATE" --print-version)" || exit $?
if [ -z "$VERSION" ]; then
  # The next patch release: a version the tree does not yet declare, so step 1 has work
  # to do and "nothing serves it" is true of the fixtures.
  VERSION="$(printf '%s' "$CURRENT" | awk -F. '{printf "%s.%s.%d", $1, $2, $3 + 1}')"
fi
printf 'walk-release: the tree is at %s; walking %s via %s order\n' "$CURRENT" "$VERSION" "$ORDER"

# ── the subject, snapshotted before anything is built ───────────────────────────────
release_tags() { printf 'v%s go/v%s rust-v%s' "$CURRENT" "$CURRENT" "$CURRENT"; }
short_sha() { git -C "$ROOT" rev-parse --short "$1^{commit}" 2>/dev/null; }

SUBJECT_LOCAL_BEFORE="$(git -C "$ROOT" for-each-ref --format='%(objectname) %(refname)' refs/tags 2>/dev/null | sort)"
SUBJECT_REMOTE_BEFORE=""
REMOTE_READABLE=0
if SUBJECT_REMOTE_BEFORE="$(git -C "$ROOT" ls-remote --tags origin 2>/dev/null)" && [ -n "$SUBJECT_REMOTE_BEFORE" ]; then
  REMOTE_READABLE=1
  SUBJECT_REMOTE_BEFORE="$(printf '%s\n' "$SUBJECT_REMOTE_BEFORE" | sort)"
fi

work="$(mktemp -d)"

# ── the guard: runs on every exit path, including a crash mid-run ──────────────────
subject_guard() {
  # bash 3.2 takes the shell's exit status from the trap's last command, so the status
  # that was already decided is captured here and returned — otherwise `exit 1` became 0.
  local rc=$? problems=0 local_leak remote_leak after
  local_leak="$(git -C "$ROOT" tag -l "*$VERSION*" 2>/dev/null)"
  [ -z "$local_leak" ] || { printf '\n❌ a %s tag exists in the working repository: %s\n' "$VERSION" "$(printf '%s' "$local_leak" | tr '\n' ' ')"; problems=$((problems + 1)); }

  if [ "$REMOTE_READABLE" -eq 1 ]; then
    after="$(git -C "$ROOT" ls-remote --tags origin 2>/dev/null | sort)"
    remote_leak="$(printf '%s\n' "$after" | grep "$VERSION" || true)"
    [ -z "$remote_leak" ] || { printf '\n❌ a %s tag reached the real remote: %s\n' "$VERSION" "$remote_leak"; problems=$((problems + 1)); }
    [ "$after" = "$SUBJECT_REMOTE_BEFORE" ] ||
      { printf '\n❌ the real remote'"'"'s tags changed during the walk-through\n'; problems=$((problems + 1)); }
  fi

  [ "$(git -C "$ROOT" for-each-ref --format='%(objectname) %(refname)' refs/tags 2>/dev/null | sort)" = "$SUBJECT_LOCAL_BEFORE" ] ||
    { printf '\n❌ the working repository'"'"'s tags changed during the walk-through\n'; problems=$((problems + 1)); }

  if [ "$problems" -eq 0 ]; then
    if [ "$REMOTE_READABLE" -eq 1 ]; then
      printf '\nnothing reached the subject: origin still at %s (%s)\n' \
        "$(release_tags | tr ' ' '/')" "$(short_sha "v$CURRENT")"
    else
      printf '\nnothing reached the subject: local refs unchanged at %s (%s); the real remote was not reachable, so it was not compared\n' \
        "$(release_tags | tr ' ' '/')" "$(short_sha "v$CURRENT")"
    fi
    return "$rc"
  fi
  printf '\n❌ walk-release: %d subject guard(s) failed — a harness that can write to its subject is not evidence\n' "$problems" >&2
  # An exit inside an EXIT trap sets the final status.
  exit 1
}
trap 'subject_guard' EXIT

# ── the scratch tree: a clone whose origin is a bare repository in the temp dir ─────
scratch="$work/clone"
git clone -q --no-hardlinks "$ROOT" "$scratch" || { echo "walk-release: cannot clone the tree" >&2; exit 2; }
git clone -q --bare "$scratch" "$work/origin.git" || { echo "walk-release: cannot create the scratch origin" >&2; exit 2; }
git -C "$scratch" remote remove origin
git -C "$scratch" remote add origin "$work/origin.git"
git_id=(-c user.email=self@test.invalid -c user.name=walk-release)
say "scratch tree: $scratch (origin: $work/origin.git — never this repository)"

# ── fixtures: our own registries, so nothing here needs the network ─────────────────
fx="$work/fixtures"
mkdir -p "$fx"
publish() {  # publish CHANNEL... — make the fixtures serve $VERSION on those channels
  local channel
  for channel in "$@"; do
    case "$channel" in
      crates) printf '{"num": "%s"}\n' "$VERSION" >"$fx/crates.json" ;;
      pypi)   printf '{"releases": {"%s": []}}\n' "$VERSION" >"$fx/pypi.json" ;;
      npm)    printf '{"versions": {"%s": {}}}\n' "$VERSION" >"$fx/npm.json" ;;
      maven)  printf '<metadata><versioning><versions><version>%s</version></versions></versioning></metadata>\n' \
                "$VERSION" >"$fx/maven.xml" ;;
      go)     printf '{"Version":"v%s"}\n' "$VERSION" >"$fx/go.info"
              printf 'gate/artifact.go\ngate/gate.go\nrigorix_gate_wasi.wasm\n' >"$fx/go.entries"
              sed -n 's/.*\*\*sha256:\*\* `\([0-9a-f]\{64\}\)`.*/\1/p' \
                "$scratch/go/gate/testdata/PROVENANCE.md" | head -1 >"$fx/go.wasm-sha256" ;;
    esac
    printf '%s\n' "$VERSION" >"$fx/latest-$channel.txt"
  done
}
unpublish() {  # unpublish CHANNEL... — the version is not there (a fresh release)
  local channel
  for channel in "$@"; do
    case "$channel" in
      crates) printf '{"versions": []}\n' >"$fx/crates.json" ;;
      pypi)   printf '{"releases": {}}\n' >"$fx/pypi.json" ;;
      npm)    printf '{"versions": {}}\n' >"$fx/npm.json" ;;
      maven)  printf '<metadata><versioning><versions><version>0.0.0</version></versions></versioning></metadata>\n' >"$fx/maven.xml" ;;
      go)     printf '{"Version":"v0.0.0"}\n' >"$fx/go.info" ;;
    esac
  done
}
printf 'rigorix_verifier/binding/__init__.py\nrigorix_verifier/_wasm/rigorix_gate_wasi.wasm\n' >"$fx/wheel-entries.txt"
unpublish crates pypi npm maven go
for channel in crates pypi npm maven go; do printf '%s\n' "$CURRENT" >"$fx/latest-$channel.txt"; done

gate() {  # gate ARGS… — the release gate against the scratch tree and the fixtures
  bash "$GATE" --root "$scratch" --fixtures "$fx" "$@"
}
expect_pass() {  # expect_pass LABEL COMMAND…
  local label="$1"; shift
  if run "$@"; then say "✅ $label"; else say "❌ $label"; failures=$((failures + 1)); fi
}
expect_says() {  # expect_says LABEL WANTED_TEXT [WANTED_RC] COMMAND…
  # A one-channel verification is `partial` by construction (the other four were not
  # asked), so its exit code is 3 whether or not the channel serves the version. The
  # subject is what it says about *that* channel — and, when given, its exit code.
  local label="$1" wanted="$2" want_rc="-" out rc; shift 2
  case "${1:-}" in [0-9]) want_rc="$1"; shift ;; esac
  printf '   $ %s\n' "$*"
  out="$("$@" 2>&1)"; rc=$?
  printf '%s\n' "$out" | sed 's/^/     /'
  case "$out" in
    *"$wanted"*) ;;
    *) say "❌ $label — did not say \"$wanted\""; failures=$((failures + 1)); return ;;
  esac
  if [ "$want_rc" != "-" ] && [ "$rc" -ne "$want_rc" ]; then
    say "❌ $label — said it, but exited $rc, not $want_rc"; failures=$((failures + 1)); return
  fi
  say "✅ $label"
}
expect_refuse() {  # expect_refuse LABEL WANTED_TEXT COMMAND…
  local label="$1" wanted="$2" out rc; shift 2
  printf '   $ %s\n' "$*"
  out="$("$@" 2>&1)"; rc=$?
  printf '%s\n' "$out" | sed 's/^/     /'
  if [ "$rc" -eq 0 ]; then
    say "❌ $label — it passed"; failures=$((failures + 1)); return
  fi
  case "$out" in
    *"$wanted"*) say "✅ $label" ;;
    *) say "❌ $label — refused, but not as \"$wanted\""; failures=$((failures + 1)) ;;
  esac
}

# ══ the two shared actions ══════════════════════════════════════════════════════════
bump_documents() {  # step 1: the documents state the version being released
  expect_refuse "refused before the documents are bumped" "do not match the version being released" \
    gate --verify-docs --expect "$VERSION"
  say "bumping the four manifests and every declared statement, as a releaser does:"
  local f
  for f in rust/Cargo.toml python/pyproject.toml typescript/package.json java/pom.xml; do
    perl -pi -e "s/\b\Q$CURRENT\E\b/$VERSION/g" "$scratch/$f"
  done
  # Markers first (`=X.Y.Z`), then whatever prose the default-deny names. No `\b`: the
  # version is matched as a substring, and `vX.Y.Z` is a statement of it.
  perl -pi -e "s/=\Q$CURRENT\E/=VERSION_PLACEHOLDER/g" \
    $(cd "$scratch" && git ls-files '*.md' | sed "s|^|$scratch/|")
  perl -pi -e "s/VERSION_PLACEHOLDER/$VERSION/g" \
    $(cd "$scratch" && git ls-files '*.md' | sed "s|^|$scratch/|")
  local attempt
  for attempt in 1 2 3; do
    gate --verify-docs --expect "$VERSION" >"$work/docs.log" 2>&1 && break
    grep -oE "^❌ [^:]+:[0-9]+ (says|states) $CURRENT" "$work/docs.log" |
      sed -E "s/^❌ (.*):([0-9]+) (says|states).*/\1 \2/" |
      while read -r file line; do
        perl -pi -e "s/\Q$CURRENT\E/$VERSION/g if \$. == $line" "$scratch/$file"
      done
    say "(attempt $attempt: updated the statements the gate named)"
  done
  expect_pass "every document states $VERSION — --verify-docs --expect passed" \
    gate --verify-docs --expect "$VERSION"
  (cd "$scratch" && git "${git_id[@]}" commit -qam "release $VERSION") || true
}

create_tags() {  # step 2 and 3: the three tags, advertised by the scratch origin
  local tag
  for tag in "v$VERSION" "go/v$VERSION" "rust-v$VERSION"; do
    git -C "$scratch" "${git_id[@]}" tag -a "$tag" -m "release $VERSION"
  done
  git -C "$scratch" push -q origin "refs/tags/*:refs/tags/*"
}

# ══ the old order, walked deliberately ══════════════════════════════════════════════
# RELEASING.md used to put the crates first and the tag second. The preflight refuses a
# version any channel already serves, so by the time the tag is pushed the release is
# impossible — which is what this mode demonstrates, with the same fixtures.
if [ "$ORDER" = "crates-first" ]; then
  step "THE OLD ORDER (RELEASING.md before #133): crates first, then the tag"
  bump_documents
  publish crates
  say "crates.io already serves $VERSION; now the tag that triggers the preflight"
  create_tags
  out="$(gate --tag "v$VERSION" 2>&1)"; rc=$?
  printf '%s\n' "$out" | sed 's/^/     /'
  if [ "$rc" -eq 0 ]; then
    say "❌ the preflight accepted a tag whose version crates.io already serves"
    failures=$((failures + 1))
  else
    case "$out" in
      *"already serve $VERSION"*) say "✅ refused, naming the channel: this is why §Order was reversed" ;;
      *) say "❌ refused, but not with the already-served message"; failures=$((failures + 1)) ;;
    esac
  fi
  if [ "$EXPECT_REFUSAL" -eq 1 ]; then
    [ "$failures" -eq 0 ] &&
      { printf '\n✅ walk-release: the crates-first order is refused by the gate, as RELEASING.md §Order now says\n'; exit 0; }
    printf '\n❌ walk-release: %d step(s) disagreed\n' "$failures"; exit 1
  fi
  printf '\n❌ walk-release: the order RELEASING.md used to state is not executable — that is the finding, and §Order now states the reverse (--expect-refusal turns this into a pass for CI)\n'
  exit 1
fi

# ══ the order RELEASING.md §Order states ════════════════════════════════════════════
step "1. documents state $VERSION — the preflight gate, no registry read"
bump_documents

step "2. tag v$VERSION — preflight: one version, annotated, nothing serving it yet"
expect_refuse "refused before the tag exists" "does not exist" gate --tag "v$VERSION"
create_tags
expect_pass "the preflight passes, naming the remote's advertisement" gate --tag "v$VERSION"

step "3. tag go/v$VERSION — the module's own tag, then its surface"
if [ -n "$(git -C "$scratch" ls-remote --tags origin "refs/tags/go/v$VERSION")" ]; then
  say "✅ go/v$VERSION is advertised by the scratch origin (a root tag does not version go/)"
else
  say "❌ go/v$VERSION is not advertised"; failures=$((failures + 1))
fi
publish go
expect_says "the proxy's zip carries gate/ and the pinned artifact" "✅ go serves $VERSION — gate/ present" 3 \
  gate --verify-published --channels go

step "4. verify the three channels this workflow publishes"
publish pypi npm maven
printf '   $ check-release.sh --verify-published --channels pypi,npm,maven\n'
partial="$(gate --verify-published --channels pypi,npm,maven 2>&1)"; partial_rc=$?
printf '%s\n' "$partial" | sed 's/^/     /'
case "$partial" in
  *"partial: 3 of 5 verified (asked: pypi,npm,maven; not asked: crates,go)"*)
    say "✅ exit $partial_rc — partial by construction, and it says so in words" ;;
  *) say "❌ the partial verdict is not the stated one"; failures=$((failures + 1)) ;;
esac

step "5. crates, by hand, schema first — after the tag, never before"
expect_refuse "crates refuses while nothing serves $VERSION (this step is last)" \
  "crates does not serve $VERSION" gate --verify-published --channels crates
publish crates
expect_says "crates serves $VERSION after the hand publish" "✅ crates serves $VERSION" 3 \
  gate --verify-published --channels crates

step "6. the complete question — all five, as the release dispatch asks it"
expect_pass "complete: 5 of 5 verified" gate --verify-published --channels crates,pypi,npm,maven,go

if [ "$failures" -gt 0 ]; then
  printf '\n❌ walk-release: %d step(s) disagreed with RELEASING.md §Order\n' "$failures"
  exit 1
fi
printf '\n✅ walk-release: six steps in RELEASING.md §Order'"'"'s order at %s — documents, tag, go/, the three channels, the crates last, then the complete question\n' "$VERSION"
