#!/usr/bin/env bash
# check-tag-shape.sh — the preflight's subject includes the ref shape a CI runner
# produces, which a local run never sees (#116).
#
# `actions/checkout` fetches the tag's commit *into* `refs/tags/<tag>` with
# `--no-tags`, so in a runner the local ref points at a commit while the remote still
# holds the annotation. The gate refused there — correctly, given what it was shown —
# and told the releaser to recreate a tag that was already correct. Twice.
#
# This script builds that shape on purpose, offline, and requires the verdict to pass
# naming the remote; then makes the remote's tag genuinely lightweight and requires
# the refusal to say so. `.ci/local-ci.sh` runs it as a step, so the shape is part of
# the evidence a local run can produce.
#
# The version is **not** typed here. It was a literal (`VERSION="0.10.0"`) until #128:
# at the next version the harness would keep building a fixture at the old one and keep
# passing, so the shape of the tag actually being released would be covered by nothing
# while `.ci/local-ci.sh` stayed green. It now asks the gate's own reader
# (`check-release.sh --print-version`), which is the one place the four manifests are
# compared — a split tree fails here with the gate's message instead of building a
# fixture around the disagreement.
#
# Usage:
#   bash scripts/check-tag-shape.sh              # the tree's own version
#   bash scripts/check-tag-shape.sh --root DIR   # the version DIR's manifests declare
#   bash scripts/check-tag-shape.sh --self-test  # prove the version tracks its source
# Exit: 0 = the annotated tag passes through the rewritten ref, and a lightweight tag
#       is refused naming the remote; 1 = either case is wrong; 2 = environment.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/scripts/check-release.sh"
VERSION_SOURCE="$ROOT"
SELF_TEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --root) VERSION_SOURCE="$2"; shift ;;
    --self-test) SELF_TEST=1 ;;
    *) echo "check-tag-shape: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

# Invoked through `bash`: the scripts in this repository are not executable bits in
# git, and a gate called directly here would fail on permissions rather than on its
# subject.
[ -f "$GATE" ] || { echo "check-tag-shape: no check-release.sh at $GATE" >&2; exit 2; }

harness() {  # SOURCE_DIR — build the runner's shape at that source's version
VERSION="$(bash "$GATE" --print-version --root "$VERSION_SOURCE")" || return $?
TAG="v$VERSION"
printf 'fixture at %s (from rust/Cargo.toml, python/pyproject.toml, typescript/package.json, java/pom.xml)\n' "$VERSION"

work="$(mktemp -d)"
trap 'rm -rf "$work" >/dev/null 2>&1 || true' EXIT
repo="$work/repo"
origin="$work/origin.git"

git_id=(-c user.email=self@test.invalid -c user.name=selftest)

# A repository at the release version, with the three annotated tags, and a bare
# remote that advertises them.
mkdir -p "$repo/rust" "$repo/python" "$repo/typescript" "$repo/java" "$work/fixtures"
printf 'version = "%s"\n' "$VERSION" >"$repo/rust/Cargo.toml"
printf 'version = "%s"\n' "$VERSION" >"$repo/python/pyproject.toml"
printf '{"version": "%s"}\n' "$VERSION" >"$repo/typescript/package.json"
printf '<project>\n  <version>%s</version>\n</project>\n' "$VERSION" >"$repo/java/pom.xml"
git -C "$repo" init -q
git -C "$repo" "${git_id[@]}" add -A
git -C "$repo" "${git_id[@]}" commit -qm "fixture $VERSION"
for tag in "$TAG" "go/$TAG" "rust-$TAG"; do
  git -C "$repo" "${git_id[@]}" tag -a "$tag" -m "release $VERSION"
done
git clone -q --bare "$repo" "$origin"
git -C "$repo" remote add origin "$origin"

# Nothing is published: the registry fixtures are empty, so the run is offline.
printf '{"versions": []}\n' >"$work/fixtures/crates.json"
printf '{"releases": {}}\n' >"$work/fixtures/pypi.json"
printf '{"versions": {}}\n' >"$work/fixtures/npm.json"
printf '<metadata><versioning><versions><version>0.1.0</version></versions></versioning></metadata>\n' \
  >"$work/fixtures/maven.xml"

# What `actions/checkout` does: the commit is fetched *into* the tag ref.
commit="$(git -C "$repo" rev-parse "$TAG^{commit}")"
git -C "$repo" update-ref "refs/tags/$TAG" "$commit"
ref_type="$(git -C "$repo" cat-file -t "refs/tags/$TAG")"
[ "$ref_type" = "commit" ] || {
  echo "check-tag-shape: the harness shape did not apply (ref is a $ref_type)" >&2
  exit 2
}

status=0
if out="$(bash "$GATE" --root "$repo" --fixtures "$work/fixtures" --tag "$TAG" 2>&1)"; then
  case "$out" in
    *"is annotated (remote:"*)
      printf '✅ the rewritten ref passes, naming the remote: %s\n' \
        "$(printf '%s\n' "$out" | grep -m1 '✅ tag:')" ;;
    *)
      echo "❌ passed without naming the remote — the verdict did not consult the advertisement"
      printf '%s\n' "$out" | tail -3
      status=1 ;;
  esac
else
  echo "❌ refused a tag the remote advertises as annotated — the runner's shape is not the subject"
  printf '%s\n' "$out" | tail -3
  status=1
fi

# The same remote, with a genuinely lightweight tag: the refusal must say so, and
# must not be the harness-rewrite message.
for tag in "$TAG" "go/$TAG" "rust-$TAG"; do
  git -C "$repo" tag -d "$tag" >/dev/null
  git -C "$origin" update-ref -d "refs/tags/$tag"
done
for tag in "$TAG" "go/$TAG" "rust-$TAG"; do
  git -C "$repo" tag "$tag" "$commit"
  git -C "$repo" push -q origin "refs/tags/$tag"
done
if out="$(bash "$GATE" --root "$repo" --fixtures "$work/fixtures" --tag "$TAG" 2>&1)"; then
  echo "❌ a lightweight tag on the remote was accepted"
  status=1
else
  case "$out" in
    *"is lightweight on the remote"*)
      printf '✅ a lightweight tag on the remote is refused as that: %s\n' \
        "$(printf '%s\n' "$out" | grep -m1 '❌ tag')" ;;
    *)
      echo "❌ refused, but not as a lightweight tag:"
      printf '%s\n' "$out" | tail -3
      status=1 ;;
  esac
fi

if [ "$status" -eq 0 ]; then
  echo "✅ tag shape ($TAG): the runner's rewritten ref passes through the remote's advertisement; a lightweight tag is refused as one"
fi
return "$status"
}

# The property the literal lost: the harness exercises the version its source declares.
# A fixture at 0.11.0 must build `v0.11.0` tags — asserted by name, because a harness at
# the wrong version passes too.
self_test() {
  local failures=0 cases=0 out
  # A global: the trap runs after `self_test` returns, when a local would be unset
  # (which is how it printed `tmp: unbound variable` over a passing run).
  SELF_TEST_TMP="$(mktemp -d)"
  tmp="$SELF_TEST_TMP"
  trap 'rm -rf "$SELF_TEST_TMP" >/dev/null 2>&1 || true' EXIT
  planted() {  # DIR VERSION [MAVEN_VERSION]
    mkdir -p "$1/rust" "$1/python" "$1/typescript" "$1/java"
    printf 'version = "%s"\n' "$2" >"$1/rust/Cargo.toml"
    printf 'version = "%s"\n' "$2" >"$1/python/pyproject.toml"
    printf '{"version": "%s"}\n' "$2" >"$1/typescript/package.json"
    printf '<project>\n  <version>%s</version>\n</project>\n' "${3:-$2}" >"$1/java/pom.xml"
  }
  planted "$tmp/eleven" 0.11.0

  cases=$((cases + 1))
  if out="$(bash "${BASH_SOURCE[0]}" --root "$tmp/eleven" 2>&1)"; then
    case "$out" in
      *"fixture at 0.11.0 (from rust/Cargo.toml"*) : ;;
      *) echo "❌ self-test [derived version]: did not build the source's version"
         printf '%s\n' "$out" | head -2; failures=$((failures + 1)) ;; esac
    case "$out" in
      *"✅ tag shape (v0.11.0)"*) : ;;
      *) echo "❌ self-test [derived version]: built a tag that is not v0.11.0"
         printf '%s\n' "$out" | tail -2; failures=$((failures + 1)) ;; esac
  else
    echo "❌ self-test [derived version]: refused a clean 0.11.0 source"
    printf '%s\n' "$out" | tail -3; failures=$((failures + 1))
  fi

  cases=$((cases + 1))
  planted "$tmp/split" 0.11.0 0.10.0
  if out="$(bash "${BASH_SOURCE[0]}" --root "$tmp/split" 2>&1)"; then
    echo "❌ self-test [split manifests]: built a fixture around a disagreement"
    failures=$((failures + 1))
  else
    case "$out" in
      *"a release is one version; bump them together"*) : ;;
      *) echo "❌ self-test [split manifests]: refused without the gate's message"
         printf '%s\n' "$out" | tail -3; failures=$((failures + 1)) ;; esac
  fi

  if [ "$failures" -gt 0 ]; then
    echo "❌ check-tag-shape self-test: $failures of $cases case(s) wrong"
    return 1
  fi
  echo "✅ check-tag-shape self-test: $cases cases — the harness builds the version its source declares (0.11.0, asserted by tag name), and a split source fails with the gate's message instead of a fixture"
  return 0
}

if [ "$SELF_TEST" -eq 1 ]; then
  self_test
  exit $?
fi

harness "$VERSION_SOURCE"
exit "$status"