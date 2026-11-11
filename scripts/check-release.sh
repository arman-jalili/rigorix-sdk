#!/usr/bin/env bash
# check-release.sh — a release has an identity before it has uploads.
#
# `publish.yml` asserted one thing: the tag matches each manifest. Two properties a
# release needs were asserted nowhere, and both have already failed here (#103):
#
#   * whether the version is new — an upload rejected by the second registry, after
#     the first has taken it, is discovered late and by hand;
#   * whether the registry serves what the tree documents — that is how
#     `rigorix-verifier` 0.9.0 came to be on PyPI without the `binding/` package and
#     the vendored artifact, with every local gate green.
#
# Modes:
#   preflight          (default) manifests agree, the tag agrees, and no channel
#                      serves this version yet. Run before the first upload.
#   --verify-published after the uploads: every channel serves it, and the PyPI
#                      wheel contains the package the README documents.
#   --self-test        the three cases, from local fixtures: already published on a
#                      channel, tag disagreeing with a manifest, clean release.
#
# Registry facts are read from the coordinate's own metadata, never from a composed
# download URL: crates.io API, PyPI JSON, npm packument, Maven maven-metadata.xml.
#
# Usage:
#   bash scripts/check-release.sh [--verify-published] [--tag TAG]
#   bash scripts/check-release.sh --self-test
#
# Exit: 0 = the release has an identity; 1 = it does not (message names the channel
# or the file); 2 = not verified (no network, no curl, or a manifest that cannot be
# read) — never 0.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TREE="$ROOT"
MODE="preflight"
TAG=""
FIXTURES=""
# Which coordinates this run is responsible for. `publish.yml` publishes PyPI, npm and
# Maven; the crates are published by hand, so requiring them there waits forever.
CHANNELS="crates,pypi,npm,maven"

while [ $# -gt 0 ]; do
  case "$1" in
    --verify-published) MODE="verify" ;;
    --self-test) MODE="self-test" ;;
    --tag) TAG="$2"; shift ;;
    --root) TREE="$2"; shift ;;
    --fixtures) FIXTURES="$2"; shift ;;
    --channels) CHANNELS="$2"; shift ;;
    *) echo "check-release: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

CRATES_MANIFEST="rust/Cargo.toml"
PY_MANIFEST="python/pyproject.toml"
NPM_MANIFEST="typescript/package.json"
MAVEN_MANIFEST="java/pom.xml"

# coordinate|channel|metadata source
CRATES_COORDINATE="rigorix-verifier"
PY_COORDINATE="rigorix-verifier"
NPM_COORDINATE="rigorix-verifier"
MAVEN_COORDINATE="eu.rigorix:rigorix-verifier"

fail() { printf '❌ %s\n' "$1" >&2; exit 1; }
unverified() { printf '⚠ not verified: %s\n' "$1" >&2; exit 2; }

read_version() {
  local file="$1" kind="$2"
  case "$kind" in
    toml) grep -m1 -E '^version[[:space:]]*=[[:space:]]*"' "$file" | sed -E 's/.*"([^"]+)".*/\1/' ;;
    json) python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$file" ;;
    xml)  sed -n 's#^  <version>\(.*\)</version>.*#\1#p' "$file" | head -1 ;;
  esac
}

manifests() {
  local crates py npm maven
  crates="$(read_version "$TREE/$CRATES_MANIFEST" toml)"
  py="$(read_version "$TREE/$PY_MANIFEST" toml)"
  npm="$(read_version "$TREE/$NPM_MANIFEST" json)"
  maven="$(read_version "$TREE/$MAVEN_MANIFEST" xml)"
  for pair in "crates:$crates:$CRATES_MANIFEST" "pypi:$py:$PY_MANIFEST" \
              "npm:$npm:$NPM_MANIFEST" "maven:$maven:$MAVEN_MANIFEST"; do
    [ -n "${pair##*:}" ] || unverified "no version could be read from ${pair##*:} (${pair%%:*})"
    printf '%s\n' "$pair"
  done
}

# The release's one version, or a failure naming the files that disagree.
release_version() {
  local first_channel="" first_version="" channel version file
  while IFS=: read -r channel version file; do
    [ -n "$version" ] || unverified "no version in $file"
    if [ -z "$first_version" ]; then
      first_channel="$channel"; first_version="$version"
    elif [ "$version" != "$first_version" ]; then
      fail "$channel says $version ($file) but $first_channel says $first_version — a release is one version; bump them together"
    fi
  done < <(manifests)
  printf '%s' "$first_version"
}

# registry_has CHANNEL VERSION → "yes" | "no" | "" (unverifiable)
registry_has() {
  local channel="$1" version="$2" body url
  if [ -n "$FIXTURES" ]; then
    case "$channel" in
      crates) body="$(cat "$FIXTURES/crates.json" 2>/dev/null)" || return 0 ;;
      pypi)   body="$(cat "$FIXTURES/pypi.json" 2>/dev/null)" || return 0 ;;
      npm)    body="$(cat "$FIXTURES/npm.json" 2>/dev/null)" || return 0 ;;
      maven)  body="$(cat "$FIXTURES/maven.xml" 2>/dev/null)" || return 0 ;;
    esac
    [ -n "$body" ] || return 0
  else
    case "$channel" in
      crates) url="https://crates.io/api/v1/crates/$CRATES_COORDINATE/$version" ;;
      pypi)   url="https://pypi.org/pypi/$PY_COORDINATE/json" ;;
      npm)    url="https://registry.npmjs.org/$NPM_COORDINATE" ;;
      maven)  url="https://repo1.maven.org/maven2/eu/rigorix/rigorix-verifier/maven-metadata.xml" ;;
    esac
    # A 404 is an answer ("this version is not there"), not a failure to read: a
    # preflight that reports "unverified" for every new version is useless.
    local code file
    file="$(mktemp)"
    code="$(curl -sS --max-time 20 -A "rigorix-sdk-release-check" -o "$file" \
      -w '%{http_code}' "$url" 2>/dev/null)" || { rm -f "$file"; return 0; }
    if [ "$code" = "404" ]; then rm -f "$file"; echo no; return 0; fi
    [ "$code" = "200" ] || { rm -f "$file"; return 0; }
    body="$(cat "$file")"; rm -f "$file"
  fi
  case "$channel" in
    crates) printf '%s' "$body" | grep -q "\"num\"[[:space:]]*:[[:space:]]*\"$version\"" && echo yes || echo no ;;
    pypi)   printf '%s' "$body" | python3 -c '
import json, sys
data = json.load(sys.stdin)
print("yes" if sys.argv[1] in data.get("releases", {}) else "no")
' "$version" ;;
    npm)    printf '%s' "$body" | python3 -c '
import json, sys
data = json.load(sys.stdin)
print("yes" if sys.argv[1] in data.get("versions", {}) else "no")
' "$version" ;;
    maven)  printf '%s' "$body" | grep -q "<version>$version</version>" && echo yes || echo no ;;
  esac
}

# The PyPI wheel must contain what the README documents — the failure mode of 0.9.0.
pypi_surface() {
  local version="$1" url work wheel entries
  if [ -n "$FIXTURES" ]; then
    entries="$(cat "$FIXTURES/wheel-entries.txt" 2>/dev/null)" || return 0
  else
    url="$(curl -fsSL --max-time 20 "https://pypi.org/pypi/$PY_COORDINATE/$version/json" 2>/dev/null |
      python3 -c '
import json, sys
data = json.load(sys.stdin)
for entry in data.get("urls", []):
    if entry.get("packagetype") == "bdist_wheel":
        print(entry["url"]); break
' 2>/dev/null)"
    [ -n "$url" ] || return 0
    work="$(mktemp -d)"
    wheel="$work/package.whl"
    curl -fsSL --max-time 60 -o "$wheel" "$url" 2>/dev/null || return 0
    entries="$(python3 -c '
import sys, zipfile
print("\n".join(zipfile.ZipFile(sys.argv[1]).namelist()))
' "$wheel" 2>/dev/null)" || return 0
  fi
  [ -n "$entries" ] || return 0
  printf '%s' "$entries" | grep -q '^rigorix_verifier/binding/__init__.py$' || {
    fail "the PyPI wheel for $version carries no rigorix_verifier/binding/ — the README documents a gate the package does not contain"
  }
  printf '%s' "$entries" | grep -q '^rigorix_verifier/_wasm/rigorix_gate_wasi\.wasm$' || {
    fail "the PyPI wheel for $version carries no vendored rigorix_gate_wasi.wasm — the binding cannot load"
  }
  echo yes
}

# Four questions about the repository, not about this script's default. #110: the
# first version compared `$TAG` (defaulted to `v$version`) with `v$version`, which
# cannot fail — it printed "the tag agrees" on a tree with no tag anywhere.
#
# Where the answers come from (#116): the **remote's advertisement**, because the
# remote is the authority on what was released. A local tag ref is not: the harness
# that runs this gate fetches the commit *into* `refs/tags/<tag>` with `--no-tags`,
# so in a runner the ref points at a commit while the remote still holds the
# annotation. Refusing there told a releaser to recreate a tag that was already
# correct, twice. `git ls-remote --tags <remote>` with no pattern prints both the tag
# object and its peeled commit for an annotated tag, and one line for a lightweight
# one; with an explicit pattern git prints no peel line at all, so the pattern form
# cannot answer this question.
version_at() {
  local ref="$1" path="$2" kind="$3" tmp
  tmp="$(mktemp)"
  if ! git -C "$TREE" show "$ref:$path" >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    echo ""
    return 0
  fi
  read_version "$tmp" "$kind"
  rm -f "$tmp"
}

# The remote's tag advertisement, once. Empty when there is no reachable remote.
remote_tags() {
  git -C "$TREE" ls-remote --tags origin 2>/dev/null
}

# Peeled commit for a tag according to the advertisement: empty means the remote has
# no annotation for it (lightweight, or absent).
remote_peeled() {
  local listing="$1" tag="$2"
  printf '%s\n' "$listing" | awk -v ref="refs/tags/$tag^{}" '$2 == ref { print $1 }'
}

tag_verdict() {
  local version="$1" listing="" have_remote=0
  local tagged="${TAG#rust-v}"; tagged="${tagged#go/v}"; tagged="${tagged#v}"
  [ -n "$TAG" ] || TAG="v$version"
  tagged="${TAG#rust-v}"; tagged="${tagged#go/v}"; tagged="${tagged#v}"

  if listing="$(remote_tags)"; then have_remote=1; fi
  local remote_object remote_commit
  remote_object="$(printf '%s\n' "$listing" | awk -v ref="refs/tags/$TAG" '$2 == ref { print $1 }')"
  remote_commit="$(remote_peeled "$listing" "$TAG")"

  local object commit source
  if [ "$have_remote" -eq 1 ] && [ -n "$remote_object" ]; then
    # 1 + 2 against the authority: the tag exists there, and it is annotated if the
    # advertisement carries a peeled entry.
    if [ -z "$remote_commit" ]; then
      fail "tag $TAG is lightweight on the remote (one advertisement entry, no refs/tags/$TAG^{}) — an annotated tag carries the tagger and the message a release is read from (git tag -a)"
    fi
    object="$remote_object"; commit="$remote_commit"
    source="remote: ${object:0:8} -> ${commit:0:8}"
  else
    # No remote answer for this tag: the local object is the remaining source, and the
    # verdict says so. A local ref pointing at a commit is *reported as that* — it is
    # what a harness rewrite looks like, and calling it "lightweight" sends the
    # releaser to redo a correct tag.
    local type
    type="$(git -C "$TREE" cat-file -t "refs/tags/$TAG" 2>/dev/null)"
    case "$type" in
      tag)
        object="$(git -C "$TREE" rev-parse --verify --quiet "refs/tags/$TAG")"
        commit="$(git -C "$TREE" rev-parse --verify --quiet "$TAG^{commit}")"
        source="local (the remote does not advertise $TAG)" ;;
      commit)
        fail "refs/tags/$TAG in this clone points at a commit, not at a tag object, and the remote does not advertise an annotation for it — that is a harness rewrite, not a lightweight tag. Inspect: git cat-file -t refs/tags/$TAG" ;;
      "")
        if [ "$have_remote" -eq 1 ]; then
          fail "tag $TAG does not exist — neither the remote nor this repository has it: git tag -a $TAG -m \"…\""
        fi
        fail "tag $TAG cannot be verified: no remote could be read and no local tag object exists — git fetch --tags origin" ;;
      *)
        fail "refs/tags/$TAG points at an unreadable object (type: $type) — inspect: git cat-file -p refs/tags/$TAG" ;;
    esac
  fi
  [ -n "$commit" ] || fail "tag $TAG does not peel to a commit"

  # The manifests at that commit are the subject; the commit may not be in a shallow
  # clone, so fetch exactly it rather than giving up.
  if ! git -C "$TREE" cat-file -e "$commit^{commit}" 2>/dev/null; then
    git -C "$TREE" fetch --quiet --no-tags origin "$commit" >/dev/null 2>&1 ||
      unverified "tag $TAG peels to $commit, which is not in this clone and could not be fetched"
  fi

  # 3. the four manifests at that commit name the version the tag names.
  local pair path kind at
  for pair in "rust/Cargo.toml:toml" "python/pyproject.toml:toml" \
              "typescript/package.json:json" "java/pom.xml:xml"; do
    path="${pair%%:*}"; kind="${pair##*:}"
    at="$(version_at "$commit" "$path" "$kind")"
    [ -n "$at" ] || fail "tag $TAG does not contain $path"
    [ "$at" = "$tagged" ] ||
      fail "tag $TAG points at a commit whose $path says $at, not $tagged — the tag names the release, so the tag and the manifests move together"
  done

  # 4. all three tags exist, by the same rule: the remote first, the local object when
  #    the remote says nothing, because a release is tagged locally and pushed after.
  local found=0 tag peeled
  for tag in "v$version" "go/v$version" "rust-v$version"; do
    peeled="$(remote_peeled "$listing" "$tag")"
    if [ -n "$peeled" ]; then
      found=$((found + 1))
    elif git -C "$TREE" rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
      found=$((found + 1))
    else
      printf '❌ tag %s is missing — a release needs v%s, go/v%s and rust-v%s together\n' \
        "$tag" "$version" "$version" "$version" >&2
    fi
  done
  [ "$found" -eq 3 ] || fail "only $found of 3 release tags exist"

  printf '✅ tag: %s is annotated (%s), peels to a commit whose manifests say %s; go/v%s and rust-v%s exist too\n' \
    "$TAG" "$source" "$version" "$version" "$version"
}

preflight() {
  local version channel answer published=0
  version="$(release_version)"
  printf '✅ manifests: one version, %s (crates, pypi, npm, maven)\n' "$version"
  tag_verdict "$version"

  for channel in crates pypi npm maven; do
    answer="$(registry_has "$channel" "$version")"
    if [ -z "$answer" ]; then
      unverified "the $channel registry could not be read for $version"
    elif [ "$answer" = "yes" ]; then
      printf '❌ %s already serves %s\n' "$channel" "$version" >&2
      published=$((published + 1))
    fi
  done
  [ "$published" -eq 0 ] ||
    fail "$published channel(s) already serve $version — a version means released content, so the release needs a new one"

  echo "✅ preflight: $version is unpublished on every channel, and its three tags agree"
}

verify_published() {
  local version channel answer missing=0 not_verified=0
  version="$(release_version)"
  tag_verdict "$version"
  for channel in crates pypi npm maven; do
    case ",$CHANNELS," in
      *",$channel,"*) ;;
      *)
        printf '⚠ %s not verified by this run (not in --channels %s)\n' "$channel" "$CHANNELS"
        not_verified=$((not_verified + 1))
        continue ;;
    esac
    answer="$(registry_has "$channel" "$version")"
    if [ -z "$answer" ]; then
      unverified "the $channel registry could not be read for $version"
    elif [ "$answer" = "no" ]; then
      printf '❌ %s does not serve %s\n' "$channel" "$version" >&2
      missing=$((missing + 1))
    else
      printf '✅ %s serves %s\n' "$channel" "$version"
    fi
  done
  [ "$missing" -eq 0 ] || fail "$missing channel(s) do not serve $version — the release is partial"
  case ",$CHANNELS," in
    *",pypi,"*) pypi_surface "$version" >/dev/null &&
      echo "✅ PyPI wheel: carries binding/ and the vendored artifact" ;;
  esac
  printf '✅ published: %s serve(s) %s' "$CHANNELS" "$version"
  [ "$not_verified" -eq 0 ] || printf ' (%d channel(s) not verified by this run)' "$not_verified"
  printf '\n'
}

self_test() {
  local tmp failures=0 cases=0 out before after

  # The verdicts are about a git repository, so the fixtures are repositories. A text
  # fixture cannot answer "does this tag exist", which is why #110's version of this
  # test passed on a tautology.
  # A repository *and a remote*: the verdict reads the remote's advertisement, so a
  # fixture without an origin cannot be the subject of the questions it asks (#116).
  fixture() {  # fixture DIR VERSION [TAG_VERSION]
    local dir="$1" version="$2" tag_version="${3:-$2}" tag
    mkdir -p "$dir/rust" "$dir/python" "$dir/typescript" "$dir/java" "$dir/fixtures"
    printf 'version = "%s"\n' "$version" >"$dir/rust/Cargo.toml"
    printf 'version = "%s"\n' "$version" >"$dir/python/pyproject.toml"
    printf '{"version": "%s"}\n' "$version" >"$dir/typescript/package.json"
    printf '<project>\n  <version>%s</version>\n</project>\n' "$version" >"$dir/java/pom.xml"
    git -C "$dir" init -q
    git -C "$dir" -c user.email=self@test.invalid -c user.name=selftest add -A
    git -C "$dir" -c user.email=self@test.invalid -c user.name=selftest commit -qm "fixture $version"
    for tag in "v$tag_version" "go/v$tag_version" "rust-v$tag_version"; do
      git -C "$dir" -c user.email=self@test.invalid -c user.name=selftest tag -a "$tag" -m "release $tag_version"
    done
    git clone -q --bare "$dir" "$dir.origin"
    git -C "$dir" remote add origin "$dir.origin"
  }
  # The harness's ref shape: the commit fetched *into* the tag ref, annotation left
  # behind in the remote. This is what `actions/checkout` produces, and what made the
  # preflight refuse a correct tag twice.
  harness_ref() {  # harness_ref DIR TAG
    local commit
    commit="$(git -C "$1" rev-parse "$2^{commit}")"
    git -C "$1" update-ref "refs/tags/$2" "$commit"
  }
  remote_delete() { git -C "$1.origin" update-ref -d "refs/tags/$2"; }
  absent() {  # fixtures where no channel serves the version
    printf '{"versions": []}\n' >"$1/fixtures/crates.json"
    printf '{"releases": {}}\n' >"$1/fixtures/pypi.json"
    printf '{"versions": {}}\n' >"$1/fixtures/npm.json"
    printf '<metadata><versioning><versions><version>0.1.0</version></versions></versioning></metadata>\n' \
      >"$1/fixtures/maven.xml"
  }
  expect_fail() {  # expect_fail LABEL WANTED_SUBSTRING TREE FIXTURES COMMAND
    # The command is a shell function, so it is invoked in command position with the
    # two variables as a temporary assignment (`TREE=… preflight`), not through `env`.
    local label="$1" wanted="$2" tree="$3" fixtures="$4" command="$5"
    cases=$((cases + 1))
    if out="$( TREE="$tree" FIXTURES="$fixtures" "$command" 2>&1 )"; then
      echo "❌ self-test [$label]: accepted"
      failures=$((failures + 1))
      return
    fi
    case "$out" in
      *"$wanted"*) ;;
      *) echo "❌ self-test [$label]: refused without naming it"
         printf '%s\n' "$out" | tail -3
         failures=$((failures + 1)) ;;
    esac
  }

  # 1. three annotated tags, a clean tree, nothing published: passes
  tmp="$(mktemp -d)"
  fixture "$tmp/ok" 0.10.0; absent "$tmp/ok"
  cases=$((cases + 1))
  if out="$(TREE="$tmp/ok" FIXTURES="$tmp/ok/fixtures" preflight 2>&1)"; then
    case "$out" in *"is unpublished on every channel"*) : ;;
      *) echo "❌ self-test [clean]: passed without the verdict"; failures=$((failures + 1)) ;; esac
  else
    echo "❌ self-test [clean]: a clean release was refused"; printf '%s\n' "$out" | tail -3
    failures=$((failures + 1))
  fi

  # 2. no tag anywhere
  tmp="$(mktemp -d)"
  fixture "$tmp/notag" 0.10.0; absent "$tmp/notag"
  for tag in v0.10.0 go/v0.10.0 rust-v0.10.0; do
    git -C "$tmp/notag" tag -d "$tag" >/dev/null
    remote_delete "$tmp/notag" "$tag"
  done
  expect_fail "no tag" "does not exist" "$tmp/notag" "$tmp/notag/fixtures" preflight

  # 3. only the v tag: the two the module layout needs are named as missing
  tmp="$(mktemp -d)"
  fixture "$tmp/partial" 0.10.0; absent "$tmp/partial"
  for tag in go/v0.10.0 rust-v0.10.0; do
    git -C "$tmp/partial" tag -d "$tag" >/dev/null
    remote_delete "$tmp/partial" "$tag"
  done
  expect_fail "one of three tags" "go/v0.10.0 is missing" "$tmp/partial" "$tmp/partial/fixtures" preflight

  # 4. the tag names 0.10.0 but points at a commit whose manifests say 0.9.0; HEAD has
  #    since moved to 0.10.0, so only the at-commit check can see it.
  tmp="$(mktemp -d)"
  fixture "$tmp/moved" 0.9.0 0.10.0; absent "$tmp/moved"
  printf 'version = "0.10.0"\n' >"$tmp/moved/rust/Cargo.toml"
  printf 'version = "0.10.0"\n' >"$tmp/moved/python/pyproject.toml"
  printf '{"version": "0.10.0"}\n' >"$tmp/moved/typescript/package.json"
  printf '<project>\n  <version>0.10.0</version>\n</project>\n' >"$tmp/moved/java/pom.xml"
  git -C "$tmp/moved" -c user.email=self@test.invalid -c user.name=selftest commit -qam "bump to 0.10.0"
  expect_fail "tag on another version" "says 0.9.0, not 0.10.0" \
    "$tmp/moved" "$tmp/moved/fixtures" preflight

  # 5. a lightweight tag carries no record
  tmp="$(mktemp -d)"
  fixture "$tmp/light" 0.10.0; absent "$tmp/light"
  for tag in v0.10.0 go/v0.10.0 rust-v0.10.0; do
    git -C "$tmp/light" tag -d "$tag" >/dev/null
    remote_delete "$tmp/light" "$tag"
    git -C "$tmp/light" tag "$tag"                      # lightweight, locally
    git -C "$tmp/light" push -q origin "refs/tags/$tag" # and on the remote
  done
  expect_fail "lightweight tag on the remote" "is lightweight on the remote" \
    "$tmp/light" "$tmp/light/fixtures" preflight

  # The harness shape passes, naming the remote: the ref points at the commit, the
  # remote holds the annotation, and the annotation is the authority (#116).
  tmp="$(mktemp -d)"
  fixture "$tmp/harness" 0.10.0; absent "$tmp/harness"
  harness_ref "$tmp/harness" v0.10.0
  cases=$((cases + 1))
  if out="$(TREE="$tmp/harness" FIXTURES="$tmp/harness/fixtures" preflight 2>&1)"; then
    case "$out" in
      *"is annotated (remote:"*) : ;;
      *) echo "❌ self-test [harness ref]: passed without naming the remote"
         printf '%s\n' "$out" | tail -2; failures=$((failures + 1)) ;;
    esac
  else
    echo "❌ self-test [harness ref]: refused a correctly annotated tag"
    printf '%s\n' "$out" | tail -3; failures=$((failures + 1))
  fi

  # An unreadable object is reported as unreadable, not as a lightweight tag.
  tmp="$(mktemp -d)"
  fixture "$tmp/unreadable" 0.10.0; absent "$tmp/unreadable"
  git -C "$tmp/unreadable" update-ref refs/tags/v0.10.0 "$(git -C "$tmp/unreadable" hash-object -w /dev/null)"
  remote_delete "$tmp/unreadable" v0.10.0
  expect_fail "unreadable object" "points at an unreadable object" \
    "$tmp/unreadable" "$tmp/unreadable/fixtures" preflight

  # 6. a version already served by a channel
  tmp="$(mktemp -d)"
  fixture "$tmp/pub" 0.10.0; absent "$tmp/pub"
  printf '{"releases": {"0.10.0": []}}\n' >"$tmp/pub/fixtures/pypi.json"
  expect_fail "already published" "pypi already serves 0.10.0" \
    "$tmp/pub" "$tmp/pub/fixtures" preflight

  # 7. manifests that disagree with each other
  tmp="$(mktemp -d)"
  fixture "$tmp/split" 0.10.0; absent "$tmp/split"
  printf 'version = "0.9.0"\n' >"$tmp/split/python/pyproject.toml"
  expect_fail "split manifests" "python/pyproject.toml" \
    "$tmp/split" "$tmp/split/fixtures" preflight

  # 8. the published wheel lacks the surface the README names (the 0.9.0 defect)
  tmp="$(mktemp -d)"
  fixture "$tmp/surface" 0.10.0; absent "$tmp/surface"
  printf 'rigorix_verifier/__init__.py\nrigorix_verifier/client/__init__.py\n' \
    >"$tmp/surface/fixtures/wheel-entries.txt"
  printf '{"releases": {"0.10.0": []}}\n' >"$tmp/surface/fixtures/pypi.json"
  printf '{"versions": {"0.10.0": {}}}\n' >"$tmp/surface/fixtures/npm.json"
  printf '{"num": "0.10.0"}\n' >"$tmp/surface/fixtures/crates.json"
  printf '<metadata><versioning><versions><version>0.10.0</version></versions></versioning></metadata>\n' \
    >"$tmp/surface/fixtures/maven.xml"
  expect_fail "wheel without binding/" "carries no rigorix_verifier/binding/" \
    "$tmp/surface" "$tmp/surface/fixtures" verify_published

  # 11. a channel outside --channels is named as not verified, not counted missing.
  #     `publish.yml` publishes three of the four; requiring crates there waited
  #     forever on the first real release.
  tmp="$(mktemp -d)"
  fixture "$tmp/subset" 0.10.0; absent "$tmp/subset"
  printf '{"releases": {"0.10.0": []}}\n' >"$tmp/subset/fixtures/pypi.json"
  printf '{"versions": {"0.10.0": {}}}\n' >"$tmp/subset/fixtures/npm.json"
  printf '<metadata><versioning><versions><version>0.10.0</version></versions></versioning></metadata>\n' \
    >"$tmp/subset/fixtures/maven.xml"
  printf 'rigorix_verifier/binding/__init__.py\nrigorix_verifier/_wasm/rigorix_gate_wasi.wasm\n' \
    >"$tmp/subset/fixtures/wheel-entries.txt"
  cases=$((cases + 1))
  if out="$( TREE="$tmp/subset" FIXTURES="$tmp/subset/fixtures" CHANNELS="pypi,npm,maven" verify_published 2>&1 )"; then
    case "$out" in
      *"⚠ crates not verified by this run"*) : ;;
      *) echo "❌ self-test [channel subset]: passed without naming the channel it skipped"
         printf '%s\n' "$out" | tail -3; failures=$((failures + 1)) ;; esac
  else
    echo "❌ self-test [channel subset]: refused — crates was counted missing though it was out of scope"
    printf '%s\n' "$out" | tail -3; failures=$((failures + 1))
  fi

  if [ "$failures" -gt 0 ]; then
    echo "❌ check-release self-test: $failures of $cases case(s) wrong"
    return 1
  fi
  echo "✅ check-release self-test: $cases cases — missing tag, partial tags, a tag on another version, a lightweight tag on the remote, an unreadable object, an already-served version, split manifests, a wheel without binding/ — each refused by name; a clean release and the harness's rewritten ref pass, naming the remote; a channel outside --channels is named, not counted missing"
  return 0
}

case "$MODE" in
  self-test) self_test; exit $? ;;
  verify) verify_published ;;
  *) preflight ;;
esac