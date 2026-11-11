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
# Usage: bash scripts/check-tag-shape.sh
# Exit: 0 = the annotated tag passes through the rewritten ref, and a lightweight tag
#       is refused naming the remote; 1 = either case is wrong; 2 = environment.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/scripts/check-release.sh"
VERSION="0.10.0"
TAG="v$VERSION"

# Invoked through `bash`: the scripts in this repository are not executable bits in
# git, and a gate called directly here would fail on permissions rather than on its
# subject.
[ -f "$GATE" ] || { echo "check-tag-shape: no check-release.sh at $GATE" >&2; exit 2; }

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
  echo "✅ tag shape: the runner's rewritten ref passes through the remote's advertisement; a lightweight tag is refused as one"
fi
exit "$status"