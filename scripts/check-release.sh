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
#                      wheel contains the package the README documents. A channel the
#                      run was not asked about is *named* and the run exits 3 — a
#                      partial check is not a green total (#120).
#   --verify-docs      after the uploads, and after the registry checks: every
#                      document that states a published version states the one its
#                      channel serves now. A release's definition of done contained no
#                      document, which is how four documents came to say the registries
#                      served 0.9.0 while they served 0.10.0 (#119).
#   --self-test        the cases, from local fixtures.
#
# Registry facts are read from the coordinate's own metadata, never from a composed
# download URL: crates.io API, PyPI JSON, npm packument, Maven maven-metadata.xml,
# and for Go the module proxy (`@v/<version>.info`). Go is a fifth channel: the
# project publishes five coordinates, and the gate knew four (#120).
#
# Usage:
#   bash scripts/check-release.sh [--verify-published] [--tag TAG]
#   bash scripts/check-release.sh --self-test
#
# Exit: 0 = the release has an identity; 1 = it does not (message names the channel
# or the file); 2 = not verified (no network, no curl, or a manifest that cannot be
# read); 3 = verified *some* channels, and named the ones it did not — never 0.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TREE="$ROOT"
MODE="preflight"
TAG=""
FIXTURES=""
# The channel set, in one place: both loops and `--channels` derive from it, so a
# sixth channel cannot be added to one and forgotten in the other (#120).
ALL_CHANNELS="crates pypi npm maven go"
# Which coordinates this run is responsible for. `publish.yml` publishes PyPI, npm and
# Maven; the crates are published by hand, so requiring them there waits forever.
CHANNELS="crates,pypi,npm,maven,go"

while [ $# -gt 0 ]; do
  case "$1" in
    --verify-published) MODE="verify" ;;
    --verify-docs) MODE="docs" ;;
    --self-test) MODE="self-test" ;;
    --tag) TAG="$2"; shift ;;
    --root) TREE="$2"; shift ;;
    --fixtures) FIXTURES="$2"; shift ;;
    --channels) CHANNELS="$2"; shift ;;
    *) echo "check-release: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

GO_MANIFEST="go/go.mod"
CRATES_MANIFEST="rust/Cargo.toml"
PY_MANIFEST="python/pyproject.toml"
NPM_MANIFEST="typescript/package.json"
MAVEN_MANIFEST="java/pom.xml"

# coordinate|channel|metadata source
CRATES_COORDINATE="rigorix-verifier"
PY_COORDINATE="rigorix-verifier"
NPM_COORDINATE="rigorix-verifier"
MAVEN_COORDINATE="eu.rigorix:rigorix-verifier"
# The module path is read from `go/go.mod`, not typed: the coordinate is whatever the
# module declares, so a rename cannot leave a stale literal here.
go_module() { awk '/^module /{print $2; exit}' "$ROOT/$GO_MANIFEST" 2>/dev/null; }

# Why an answer is missing, when the answer is not a plain yes/no. It travels through a
# file because `registry_has` is called in a command substitution: a shell function
# that sets a variable inside `$( )` sets it in a subshell, and the caller never sees
# it — which is exactly how the first version of this reported "could not be read" for
# a proxy that had answered 404.
REASON_FILE="$(mktemp "${TMPDIR:-/tmp}/rigorix-reason.XXXXXX")"
# The version the *tag* names, set by `tag_verdict`. `--verify-published --tag vX` must
# ask about vX: it read the tree's version instead, so a dispatch told to check 0.9.0
# verified 0.10.0 and printed ✅. That is the same defect as #110 — a verdict about the
# script's default rather than about the subject it was given — one layer down.
TAG_VERSION=""

fail() { printf '❌ %s\n' "$1" >&2; exit 1; }
# The version a channel serves *now* — not "does it serve this one". A document is
# stale when the channel has moved past it, and `registry_has` cannot see that: every
# older version is still served forever.
registry_latest() {
  local channel="$1" url body code file
  if [ -n "$FIXTURES" ]; then
    body="$(cat "$FIXTURES/latest-$channel.txt" 2>/dev/null || true)"
    [ -n "$body" ] || {
      printf '%s' "no fixture latest-$channel.txt — the served version cannot be read" >"$REASON_FILE"
      return 0; }
    printf '%s' "$body"
    return 0
  fi
  case "$channel" in
    crates) url="https://crates.io/api/v1/crates/$CRATES_COORDINATE" ;;
    pypi)   url="https://pypi.org/pypi/$PY_COORDINATE/json" ;;
    npm)    url="https://registry.npmjs.org/$NPM_COORDINATE" ;;
    maven)  url="https://repo1.maven.org/maven2/eu/rigorix/rigorix-verifier/maven-metadata.xml" ;;
    go)     url="https://proxy.golang.org/$(go_module)/@latest" ;;
  esac
  file="$(mktemp)"
  code="$(curl -sS --max-time 20 -A "rigorix-sdk-release-check" -o "$file" -w '%{http_code}' "$url" 2>/dev/null)" || {
    rm -f "$file"; printf '%s' "could not reach the $channel registry" >"$REASON_FILE"; return 0; }
  [ "$code" = "200" ] || {
    rm -f "$file"; printf '%s' "the $channel registry answered $code" >"$REASON_FILE"; return 0; }
  body="$(cat "$file")"; rm -f "$file"
  case "$channel" in
    crates) printf '%s' "$body" | python3 -c 'import json,sys;print(json.load(sys.stdin)["crate"]["max_stable_version"])' 2>/dev/null ;;
    pypi)   printf '%s' "$body" | python3 -c 'import json,sys;print(json.load(sys.stdin)["info"]["version"])' 2>/dev/null ;;
    npm)    printf '%s' "$body" | python3 -c 'import json,sys;print(json.load(sys.stdin)["dist-tags"]["latest"])' 2>/dev/null ;;
    maven)  printf '%s' "$body" | sed -n 's#.*<release>\(.*\)</release>.*#\1#p' | head -1 ;;
    go)     printf '%s' "$body" | python3 -c 'import json,sys;print(json.load(sys.stdin)["Version"].lstrip("v"))' 2>/dev/null ;;
  esac
}

# Every document states each published version once, on a line a machine can read:
#   <!-- published: pypi=0.10.0 npm=0.10.0 maven=0.10.0 go=0.10.0 crates=0.10.0 -->
# The prose around it says "the published version" instead of repeating the number, so
# there is one copy of the fact per document and the check has one place to read.
docs_mode() {
  local files file line_no line marker pair channel declared served checked=0 wrong=0 unreadable=0
  files="$(cd "$TREE" && git ls-files '*.md' 2>/dev/null)"
  [ -n "$files" ] || files="$(cd "$TREE" && find . -name '*.md' -not -path './.git/*' | sed 's|^\./||')"
  [ -n "$files" ] || fail "no subject, not evidence: no Markdown file could be listed under $TREE"
  while IFS= read -r file; do
    [ -f "$TREE/$file" ] || continue
    while IFS=: read -r line_no line; do
      marker="${line#*published:}"; marker="${marker%%-->*}"
      for pair in $marker; do
        channel="${pair%%=*}"; declared="${pair#*=}"
        case " $ALL_CHANNELS " in
          *" $channel "*) ;;
          *) fail "$file:$line_no names an unknown channel '$channel' — the channels are: $(printf '%s' "$ALL_CHANNELS" | tr ' ' ',')" ;;
        esac
        [ -n "$declared" ] || fail "$file:$line_no states no version for $channel"
        served="$(registry_latest "$channel")"
        if [ -z "$served" ]; then
          printf '⚠ %s:%s: %s declares %s, and %s could not be read (%s)\n' \
            "$file" "$line_no" "$channel" "$declared" "$channel" "$(reason_for "$channel" "$declared")" >&2
          unreadable=$((unreadable + 1)); continue
        fi
        checked=$((checked + 1))
        if [ "$served" != "$declared" ]; then
          printf '❌ %s:%s says %s for %s, but %s serves %s\n' \
            "$file" "$line_no" "$declared" "$channel" "$channel" "$served" >&2
          wrong=$((wrong + 1))
        else
          printf '✅ %s %s:%s declares %s, and %s serves it\n' "$channel" "$file" "$line_no" "$declared" "$channel"
        fi
      done
    # Fenced blocks are examples, not claims: a document that *shows* the marker
    # syntax inside a code fence would otherwise be checked as if it declared a
    # version, which is a second copy of the fact in the same file.
    done < <(awk '
      /^[[:space:]]*```/ { fence = !fence; next }
      !fence && /<!-- published:/ { print NR ": " $0 }
    ' "$TREE/$file" 2>/dev/null)
  done <<< "$files"
  [ "$checked" -gt 0 ] || fail "no subject, not evidence: no document declares a published version, so nothing was compared"
  [ "$wrong" -eq 0 ] || fail "$wrong statement(s) about a published version are stale — a release updates the documents that state it"
  # No network: the documents were not compared, and that is not a pass.
  [ "$unreadable" -eq 0 ] || {
    printf '⚠ %d channel(s) could not be read; the documents were not compared against them\n' "$unreadable" >&2
    exit 3; }
  printf '✅ documents: %d version statement(s) agree with the registries\n' "$checked"
}

reason_for() {  # the recorded reason, or a plain one naming the channel
  local recorded; recorded="$(cat "$REASON_FILE" 2>/dev/null)"
  printf '%s' "${recorded:-the $1 registry could not be read for $2}"
}
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
      go)
        body="$(cat "$FIXTURES/go.info" 2>/dev/null || true)"
        # A fixture without `go.info` is the proxy's 404 — the case that must not be
        # read as "not published", because the proxy conflates absence with failure.
        if [ -z "$body" ] ||
           ! printf '%s' "$body" | grep -q "\"Version\"[[:space:]]*:[[:space:]]*\"v$version\""; then
          printf '%s' "the Go proxy answers 404 for $(go_module)@v$version — the proxy conflates \"no such version\" with \"cannot fetch\", so this is not evidence either way: curl https://proxy.golang.org/$(go_module)/@v/v$version.info" >"$REASON_FILE"
          return 0
        fi
        echo yes; return 0 ;;
    esac
    [ -n "$body" ] || return 0
  else
    case "$channel" in
      crates) url="https://crates.io/api/v1/crates/$CRATES_COORDINATE/$version" ;;
      pypi)   url="https://pypi.org/pypi/$PY_COORDINATE/json" ;;
      npm)    url="https://registry.npmjs.org/$NPM_COORDINATE" ;;
      maven)  url="https://repo1.maven.org/maven2/eu/rigorix/rigorix-verifier/maven-metadata.xml" ;;
      go)     url="https://proxy.golang.org/$(go_module)/@v/v$version.info" ;;
    esac
    # A 404 is an answer ("this version is not there"), not a failure to read: a
    # preflight that reports "unverified" for every new version is useless.
    local code file
    file="$(mktemp)"
    code="$(curl -sS --max-time 20 -A "rigorix-sdk-release-check" -o "$file" \
      -w '%{http_code}' "$url" 2>/dev/null)" ||
      { rm -f "$file"; printf '%s' "could not reach the $channel registry for $version" >"$REASON_FILE"; return 0; }
    if [ "$code" = "404" ]; then
      rm -f "$file"
      # For a registry that lists versions, 404 is the answer "not published here".
      # For the Go proxy it is not: the same 404 covers a module it cannot fetch.
      if [ "$channel" = "go" ]; then
        printf '%s' "the Go proxy answers 404 for $(go_module)@v$version — the proxy conflates \"no such version\" with \"cannot fetch\", so this is not evidence either way: curl https://proxy.golang.org/$(go_module)/@v/v$version.info" >"$REASON_FILE"
        return 0
      fi
      echo no; return 0
    fi
    [ "$code" = "200" ] ||
      { rm -f "$file"; printf '%s' "the $channel registry answered $code for $version" >"$REASON_FILE"; return 0; }
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
    # A 200 from `@v/<version>.info` means the proxy holds that version; the body says
    # which one, so it is compared rather than assumed.
    go)     printf '%s' "$body" | grep -q "\"Version\"[[:space:]]*:[[:space:]]*\"v$version\"" && echo yes || echo no ;;
  esac
}

# The Go module's own surface: `gate/` present in the zip the proxy serves, and the
# vendored wasm the pinned digest names. The pin is *read* from PROVENANCE.md so the
# digest has one copy in this repository, not two.
pinned_wasm_digest() {
  sed -n 's/.*\*\*sha256:\*\* `\([0-9a-f]\{64\}\)`.*/\1/p' \
    "$ROOT/go/gate/testdata/PROVENANCE.md" 2>/dev/null | head -1
}

go_surface() {
  local version="$1" pin entries="" got="" work zip mod
  pin="$(pinned_wasm_digest)"
  [ -n "$pin" ] || unverified "no pinned wasm digest could be read from go/gate/testdata/PROVENANCE.md"
  if [ -n "$FIXTURES" ]; then
    entries="$(cat "$FIXTURES/go.entries" 2>/dev/null || true)"
    got="$(cat "$FIXTURES/go.wasm-sha256" 2>/dev/null || true)"
    [ -n "$entries" ] || return 0
  else
    work="$(mktemp -d)"; zip="$work/module.zip"
    curl -fsSL --max-time 90 -o "$zip" \
      "https://proxy.golang.org/$(go_module)/@v/v$version.zip" 2>/dev/null || {
        rm -f "$zip"; return 0; }
    # Every member is prefixed with `<module>@<version>/`, and the module path has
    # slashes in it — so the prefix is stripped by its exact length, not at the first
    # slash.
    mod="$(go_module)"
    read -r entries got <<EOF
$(python3 - "$zip" "$mod@v$version/" <<'PY' 2>/dev/null
import hashlib, sys, zipfile
prefix = sys.argv[2]
z = zipfile.ZipFile(sys.argv[1])
names = [n[len(prefix):] if n.startswith(prefix) else n for n in z.namelist()]
wasm = [n for n in z.namelist() if n.endswith("rigorix_gate_wasi.wasm")]
digest = hashlib.sha256(z.read(wasm[0])).hexdigest() if wasm else ""
print("\x1f".join(names), digest)
PY
)
EOF
    rm -f "$zip"
    entries="$(printf '%s' "$entries" | tr '\037' '\n')"
    [ -n "$entries" ] || return 0
  fi
  printf '%s' "$entries" | grep -q '^gate/' ||
    fail "the Go module $(go_module)@v$version carries no gate/ — the README documents a gate the module does not contain"
  if [ -n "$got" ] && [ "$got" != "$pin" ]; then
    fail "the Go module's vendored wasm hashes to ${got:0:8}…, the pin in go/gate/testdata/PROVENANCE.md is ${pin:0:8}…"
  fi
  printf 'gate/ present, wasm %s…\n' "${pin:0:8}"
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
  TAG_VERSION="$tagged"

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
    "$TAG" "$source" "$tagged" "$version" "$version"
}

preflight() {
  local version channel answer published=0 asked=""
  version="$(release_version)"
  printf '✅ manifests: one version, %s (%s)\n' "$version" "$(printf '%s' "$ALL_CHANNELS" | tr ' ' ',')"
  tag_verdict "$version"
  # Preflight's subject is the version about to be uploaded, so a tag naming a
  # different one is not a cosmetic mismatch: the uploads would ship the tree's version
  # under a tag for another.
  [ "$TAG_VERSION" = "$version" ] ||
    fail "--tag $TAG names $TAG_VERSION but the tree says $version — a release tag names the version it ships"

  for channel in $ALL_CHANNELS; do
    # Go cannot answer this question: `go/v<version>` is served by the proxy the
    # moment the tag is pushed, i.e. before any upload, so "is it unpublished" has no
    # answer there. It is said, not omitted (#120).
    [ "$channel" = "go" ] && continue
    asked="$asked${asked:+, }$channel"
    answer="$(registry_has "$channel" "$version")"
    if [ -z "$answer" ]; then
      unverified "$(reason_for "$channel" "$version")"
    elif [ "$answer" = "yes" ]; then
      printf '❌ %s already serves %s\n' "$channel" "$version" >&2
      published=$((published + 1))
    fi
  done
  [ "$published" -eq 0 ] ||
    fail "$published channel(s) already serve $version — a version means released content, so the release needs a new one"

  printf '✅ preflight: %s is unpublished on %s (go: tag-driven, verified after upload), and its three tags agree\n' \
    "$version" "$asked"
}

# What would settle a channel this run was not asked about, or answered "not yet".
settle_with() {
  case "$1" in
    crates) echo "cargo publish" ;;
    go)     echo "push go/v\$version" ;;
    *)      echo "the publish workflow's $1 upload job" ;;
  esac
}

verify_published() {
  local version channel answer missing=0 verified=0 skipped="" skipped_n=0 total=0
  version="$(release_version)"
  tag_verdict "$version"
  # The subject is the version the tag names — which is the tree's on a tag push, and
  # the checked-out branch's otherwise, so `--tag` must decide it.
  if [ "$TAG_VERSION" != "$version" ]; then
    printf '✅ subject: %s names %s, so %s is what this run asks about (the tree says %s)\n' \
      "$TAG" "$TAG_VERSION" "$TAG_VERSION" "$version"
    version="$TAG_VERSION"
  fi
  total="$(printf '%s\n' $ALL_CHANNELS | wc -l | tr -d ' ')"
  for channel in $ALL_CHANNELS; do
    case ",$CHANNELS," in
      *",$channel,"*) ;;
      *)
        # Named, with the observable that would settle it, and counted.
        skipped="$skipped${skipped:+, }$channel: $(settle_with "$channel" | sed "s/\\\$version/v$version/")"
        skipped_n=$((skipped_n + 1))
        continue ;;
    esac
    answer="$(registry_has "$channel" "$version")"
    if [ -z "$answer" ]; then
      unverified "$(reason_for "$channel" "$version")"
    elif [ "$answer" = "no" ]; then
      printf '❌ %s does not serve %s\n' "$channel" "$version" >&2
      missing=$((missing + 1))
    elif [ "$channel" = "go" ]; then
      local surface
      surface="$(go_surface "$version")" || exit $?
      printf '✅ go serves %s — %s\n' "$version" "$surface"
      verified=$((verified + 1))
    else
      printf '✅ %s serves %s\n' "$channel" "$version"
      verified=$((verified + 1))
    fi
  done
  [ "$missing" -eq 0 ] ||
    fail "$missing channel(s) do not serve $version — the release is partial"
  case ",$CHANNELS," in
    *",pypi,"*) pypi_surface "$version" >/dev/null &&
      echo "✅ PyPI wheel: carries binding/ and the vendored artifact" ;;
  esac
  # A run that skipped a channel has not verified the release, however many of the
  # others answered: exit 3, the `--allow-skips` convention, and no `✅ published:`.
  if [ "$skipped_n" -gt 0 ]; then
    printf '⚠ %d of %d verified; %d not verified (%s)\n' "$verified" "$total" "$skipped_n" "$skipped" >&2
    exit 3
  fi
  printf '✅ published: %s serve(s) %s\n' "$(printf '%s' "$ALL_CHANNELS" | tr ' ' ',')" "$version"
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
  served() {  # served DIR VERSION — every channel answers, and Go carries its surface
    local dir="$1" v="$2"
    printf '{"num": "%s"}\n' "$v" >"$dir/fixtures/crates.json"
    printf '{"releases": {"%s": []}}\n' "$v" >"$dir/fixtures/pypi.json"
    printf '{"versions": {"%s": {}}}\n' "$v" >"$dir/fixtures/npm.json"
    printf '<metadata><versioning><versions><version>%s</version></versions></versioning></metadata>\n' \
      "$v" >"$dir/fixtures/maven.xml"
    printf '{"Version":"v%s"}\n' "$v" >"$dir/fixtures/go.info"
    printf 'gate/artifact.go\ngate/gate.go\nrigorix_gate_wasi.wasm\n' >"$dir/fixtures/go.entries"
    pinned_wasm_digest >"$dir/fixtures/go.wasm-sha256"
    printf 'rigorix_verifier/binding/__init__.py\nrigorix_verifier/_wasm/rigorix_gate_wasi.wasm\n' \
      >"$dir/fixtures/wheel-entries.txt"
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
    case "$out" in *"is unpublished on crates, pypi, npm, maven (go: tag-driven"*) : ;;
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
  served "$tmp/surface" 0.10.0
  printf 'rigorix_verifier/__init__.py\nrigorix_verifier/client/__init__.py\n' \
    >"$tmp/surface/fixtures/wheel-entries.txt"
  expect_fail "wheel without binding/" "carries no rigorix_verifier/binding/" \
    "$tmp/surface" "$tmp/surface/fixtures" verify_published

  # 11. A subset run is not a green total: it names what it did not verify, with the
  #     observable that would settle it, and exits 3 (the `--allow-skips` convention).
  tmp="$(mktemp -d)"
  fixture "$tmp/subset" 0.10.0; served "$tmp/subset" 0.10.0
  cases=$((cases + 1))
  out="$( TREE="$tmp/subset" FIXTURES="$tmp/subset/fixtures" CHANNELS="pypi,npm,maven,go" verify_published 2>&1 )"
  rc=$?
  if [ "$rc" -ne 3 ]; then
    echo "❌ self-test [subset run]: exit $rc, expected 3 (a partial check is not a green total)"
    printf '%s\n' "$out" | tail -3; failures=$((failures + 1))
  else
    case "$out" in
      *"⚠ 4 of 5 verified; 1 not verified (crates: cargo publish)"*) : ;;
      *) echo "❌ self-test [subset run]: exit 3 without naming the channel and its remedy"
         printf '%s\n' "$out" | tail -3; failures=$((failures + 1)) ;; esac
    case "$out" in
      *"✅ published:"*) echo "❌ self-test [subset run]: printed a green total for a partial check"
         failures=$((failures + 1)) ;; esac
  fi

  # 12. the Go proxy's 404 is not an answer: it covers "no such version" and "cannot
  #     fetch" alike, so it is reported as unverified, naming the coordinate.
  tmp="$(mktemp -d)"
  fixture "$tmp/go404" 0.10.0; served "$tmp/go404" 0.10.0
  rm -f "$tmp/go404/fixtures/go.info"
  expect_fail "go proxy 404" "$(go_module)@v0.10.0" \
    "$tmp/go404" "$tmp/go404/fixtures" verify_published

  # 13. the module is served but carries no gate/: the README documents a gate the
  #     coordinate does not contain.
  tmp="$(mktemp -d)"
  fixture "$tmp/nogatedir" 0.10.0; served "$tmp/nogatedir" 0.10.0
  printf 'anchor.go\ncanonical.go\nrigorix_gate_wasi.wasm\n' >"$tmp/nogatedir/fixtures/go.entries"
  expect_fail "go module without gate/" "carries no gate/" \
    "$tmp/nogatedir" "$tmp/nogatedir/fixtures" verify_published

  # 14. the module's wasm is not the pinned artifact
  tmp="$(mktemp -d)"
  fixture "$tmp/godigest" 0.10.0; served "$tmp/godigest" 0.10.0
  printf '0000000000000000000000000000000000000000000000000000000000000000\n' \
    >"$tmp/godigest/fixtures/go.wasm-sha256"
  expect_fail "go wasm digest" "the pin in go/gate/testdata/PROVENANCE.md is" \
    "$tmp/godigest" "$tmp/godigest/fixtures" verify_published

  # 15. a document that states a version its channel has moved past. The failure mode
  #     of #119: the registries answered 0.9.0 in four files while they served 0.10.0.
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/docs"
  printf '# doc\n<!-- published: pypi=0.9.0 -->\nprose\n' >"$tmp/docs/README.md"
  for channel in crates pypi npm maven go; do printf '0.10.0\n' >"$tmp/docs/fixtures-latest-$channel.txt"; done
  mkdir -p "$tmp/docs/fx"
  for channel in crates pypi npm maven go; do printf '0.10.0\n' >"$tmp/docs/fx/latest-$channel.txt"; done
  cases=$((cases + 1))
  out="$( TREE="$tmp/docs" FIXTURES="$tmp/docs/fx" docs_mode 2>&1 )"
  rc=$?
  if [ "$rc" -ne 1 ]; then
    echo "❌ self-test [stale document]: exit $rc, expected 1"
    printf '%s\n' "$out" | tail -3; failures=$((failures + 1))
  else
    case "$out" in
      *"README.md:2 says 0.9.0 for pypi, but pypi serves 0.10.0"*) : ;;
      *) echo "❌ self-test [stale document]: refused without naming the file, the line and both versions"
         printf '%s\n' "$out" | tail -3; failures=$((failures + 1)) ;; esac
  fi

  # 16. the same document stating what the channel serves: passes
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/docs/ok/fx"
  printf '# doc\n<!-- published: pypi=0.10.0 go=0.10.0 -->\n' >"$tmp/docs/ok/README.md"
  for channel in crates pypi npm maven go; do printf '0.10.0\n' >"$tmp/docs/ok/fx/latest-$channel.txt"; done
  cases=$((cases + 1))
  if out="$( TREE="$tmp/docs/ok" FIXTURES="$tmp/docs/ok/fx" docs_mode 2>&1 )"; then
    case "$out" in *"2 version statement(s) agree"*) : ;;
      *) echo "❌ self-test [current document]: passed without counting what it compared"
         printf '%s\n' "$out" | tail -2; failures=$((failures + 1)) ;; esac
  else
    echo "❌ self-test [current document]: refused a document that agrees"
    printf '%s\n' "$out" | tail -3; failures=$((failures + 1))
  fi

  # 16b. a marker inside a fenced block is an example, not a claim: it is neither
  #      counted nor failed, so the document keeps one copy of the fact.
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/docs/fenced/fx"
  printf '# doc\n<!-- published: pypi=0.10.0 -->\n\n```\n<!-- published: pypi=0.9.0 -->\n```\n' \
    >"$tmp/docs/fenced/README.md"
  for channel in crates pypi npm maven go; do printf '0.10.0\n' >"$tmp/docs/fenced/fx/latest-$channel.txt"; done
  cases=$((cases + 1))
  if out="$( TREE="$tmp/docs/fenced" FIXTURES="$tmp/docs/fenced/fx" docs_mode 2>&1 )"; then
    case "$out" in
      *"1 version statement(s) agree"*) : ;;
      *) echo "❌ self-test [fenced example]: counted or missed a marker it should have ignored"
         printf '%s\n' "$out" | tail -3; failures=$((failures + 1)) ;; esac
  else
    echo "❌ self-test [fenced example]: refused an example inside a code fence"
    printf '%s\n' "$out" | tail -3; failures=$((failures + 1))
  fi

  # 16c. `--verify-published --tag v0.9.0` asks about 0.9.0, not about the tree's
  #      0.10.0: the verdict is about the subject it was given (#110, one layer down).
  tmp="$(mktemp -d)"
  fixture "$tmp/tagver" 0.9.0          # tagged v0.9.0, go/v0.9.0, rust-v0.9.0
  served "$tmp/tagver" 0.9.0
  printf '{"Version":"v0.9.0"}\n' >"$tmp/tagver/fixtures/go.info"
  # then the tree moves to 0.10.0 and is tagged, which is what a dispatch on a branch
  # looks like: the checked-out tree is ahead of the tag being checked.
  printf 'version = "0.10.0"\n' >"$tmp/tagver/rust/Cargo.toml"
  printf 'version = "0.10.0"\n' >"$tmp/tagver/python/pyproject.toml"
  printf '{"version": "0.10.0"}\n' >"$tmp/tagver/typescript/package.json"
  printf '<project>\n  <version>0.10.0</version>\n</project>\n' >"$tmp/tagver/java/pom.xml"
  git -C "$tmp/tagver" -c user.email=self@test.invalid -c user.name=selftest commit -qam "bump to 0.10.0"
  for tag in v0.10.0 go/v0.10.0 rust-v0.10.0; do
    git -C "$tmp/tagver" -c user.email=self@test.invalid -c user.name=selftest tag -a "$tag" -m "release 0.10.0"
  done
  cases=$((cases + 1))
  if out="$( TREE="$tmp/tagver" FIXTURES="$tmp/tagver/fixtures" TAG="v0.9.0" verify_published 2>&1 )"; then
    case "$out" in
      *"✅ pypi serves 0.9.0"*) : ;;
      *) echo "❌ self-test [--tag decides the version]: verified something other than the tag's version"
         printf '%s\n' "$out" | tail -4; failures=$((failures + 1)) ;; esac
  else
    echo "❌ self-test [--tag decides the version]: refused a published 0.9.0"
    printf '%s\n' "$out" | tail -4; failures=$((failures + 1))
  fi

  # 17. a tree with no marker at all: nothing was compared, which is not a pass
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/docs/empty/fx"
  printf '# doc, no marker\n' >"$tmp/docs/empty/README.md"
  expect_fail "no published marker" "no subject, not evidence" \
    "$tmp/docs/empty" "$tmp/docs/empty/fx" docs_mode

  # 18. a channel that cannot be read: the documents were not compared, so exit 3 —
  #     never the green line of a check that did not happen.
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/docs/offline/fx"
  # The marker names two channels; only one of them can be read.
  printf '# doc\n<!-- published: pypi=0.10.0 maven=0.10.0 -->\n' >"$tmp/docs/offline/README.md"
  printf '0.10.0\n' >"$tmp/docs/offline/fx/latest-pypi.txt"
  cases=$((cases + 1))
  out="$( TREE="$tmp/docs/offline" FIXTURES="$tmp/docs/offline/fx" docs_mode 2>&1 )"
  rc=$?
  if [ "$rc" -ne 3 ]; then
    echo "❌ self-test [unreadable registry]: exit $rc, expected 3"
    printf '%s\n' "$out" | tail -3; failures=$((failures + 1))
  else
    case "$out" in
      *"documents were not compared"*) : ;;
      *) echo "❌ self-test [unreadable registry]: exit 3 without saying what it did not compare"
         printf '%s\n' "$out" | tail -3; failures=$((failures + 1)) ;; esac
  fi

  if [ "$failures" -gt 0 ]; then
    echo "❌ check-release self-test: $failures of $cases case(s) wrong"
    return 1
  fi
  echo "✅ check-release self-test: $cases cases — missing tag, partial tags, a tag on another version, a lightweight tag on the remote, an unreadable object, an already-served version, split manifests, a wheel without binding/ — each refused by name; a clean release and the harness's rewritten ref pass, naming the remote; a channel outside --channels is named with its remedy and exits 3 rather than printing a green total; a Go proxy 404, a module without gate/ and a wasm that is not the pinned artifact are each refused by name; a document that states a stale version, a tree with no such statement, and a registry that cannot be read are each reported as what they are"
  return 0
}

case "$MODE" in
  self-test) self_test; exit $? ;;
  docs) docs_mode ;;
  verify) verify_published ;;
  *) preflight ;;
esac