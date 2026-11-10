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

while [ $# -gt 0 ]; do
  case "$1" in
    --verify-published) MODE="verify" ;;
    --self-test) MODE="self-test" ;;
    --tag) TAG="$2"; shift ;;
    --root) TREE="$2"; shift ;;
    --fixtures) FIXTURES="$2"; shift ;;
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

tag_verdict() {
  local version="$1"
  [ -n "$TAG" ] || TAG="v$version"
  case "$TAG" in
    "v$version") : ;;
    *) fail "tag $TAG disagrees with the manifests ($version, $CRATES_MANIFEST) — the tag names the release, so it must be v$version" ;;
  esac
  printf '✅ tag: %s names the manifest version %s (' "$TAG" "$version"
  printf '%s' "$CRATES_MANIFEST"
  printf ')\n'
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

  echo "✅ preflight: $version is unpublished on every channel, and the tag agrees"
  echo "   next: tag v$version, go/v$version and rust-v$version, then publish"
}

verify_published() {
  local version channel answer missing=0
  version="$(release_version)"
  tag_verdict "$version"
  for channel in crates pypi npm maven; do
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
  pypi_surface "$version" >/dev/null && echo "✅ PyPI wheel: carries binding/ and the vendored artifact"
  echo "✅ published: every channel serves $version"
}

self_test() {
  local tmp failures=0 out version
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp' >/dev/null 2>&1 || true" EXIT

  tree() {  # a clean tree at $1, version $2
    mkdir -p "$1/rust" "$1/python" "$1/typescript" "$1/java" "$1/fixtures"
    printf 'version = "%s"\n' "$2" >"$1/rust/Cargo.toml"
    printf 'version = "%s"\n' "$2" >"$1/python/pyproject.toml"
    printf '{"version": "%s"}\n' "$2" >"$1/typescript/package.json"
    printf '<project>\n  <version>%s</version>\n</project>\n' "$2" >"$1/java/pom.xml"
  }
  absent() {  # fixtures where nothing serves the version
    printf '{"versions": []}\n' >"$1/fixtures/crates.json"
    printf '{"releases": {}}\n' >"$1/fixtures/pypi.json"
    printf '{"versions": {}}\n' >"$1/fixtures/npm.json"
    printf '<metadata><versioning><versions><version>0.1.0</version></versions></versioning></metadata>\n' \
      >"$1/fixtures/maven.xml"
  }

  # 1. a clean release passes
  tree "$tmp/clean" 0.10.0; absent "$tmp/clean"
  if out="$(TREE="$tmp/clean" FIXTURES="$tmp/clean/fixtures" preflight 2>&1)"; then
    case "$out" in *"is unpublished on every channel"*) : ;;
      *) echo "❌ self-test: the clean release passed without the verdict"; failures=$((failures + 1)) ;; esac
  else
    echo "❌ self-test: a clean release was refused"; printf '%s\n' "$out" | tail -3; failures=$((failures + 1))
  fi

  # 2. a version already on a channel fails, naming the channel
  tree "$tmp/published" 0.10.0; absent "$tmp/published"
  printf '{"releases": {"0.10.0": []}}\n' >"$tmp/published/fixtures/pypi.json"
  if out="$(TREE="$tmp/published" FIXTURES="$tmp/published/fixtures" preflight 2>&1)"; then
    echo "❌ self-test: an already-published version was accepted"; failures=$((failures + 1))
  else
    case "$out" in *"pypi already serves 0.10.0"*) : ;;
      *) echo "❌ self-test: refused without naming the channel"; failures=$((failures + 1)) ;; esac
  fi

  # 3. a tag that disagrees with a manifest fails, naming both
  tree "$tmp/tag" 0.10.0; absent "$tmp/tag"
  if out="$(TREE="$tmp/tag" FIXTURES="$tmp/tag/fixtures" TAG=v0.9.0 preflight 2>&1)"; then
    echo "❌ self-test: a tag that disagrees with the manifest was accepted"; failures=$((failures + 1))
  else
    case "$out" in *"tag v0.9.0 disagrees with the manifests (0.10.0"*) : ;;
      *) echo "❌ self-test: the tag refusal did not name both"; printf '%s\n' "$out" | head -2; failures=$((failures + 1)) ;; esac
  fi

  # 4. manifests that disagree fail, naming both files
  tree "$tmp/split" 0.10.0
  printf 'version = "0.9.0"\n' >"$tmp/split/python/pyproject.toml"
  if out="$(TREE="$tmp/split" FIXTURES="$tmp/split/fixtures" preflight 2>&1)"; then
    echo "❌ self-test: disagreeing manifests were accepted"; failures=$((failures + 1))
  else
    case "$out" in *"python/pyproject.toml"*) : ;;
      *) echo "❌ self-test: the manifest refusal did not name the file"; failures=$((failures + 1)) ;; esac
  fi

  # 5. the PyPI surface check catches the 0.9.0 defect: a wheel with no binding/
  tree "$tmp/surface" 0.10.0; absent "$tmp/surface"
  printf 'rigorix_verifier/__init__.py\nrigorix_verifier/client/__init__.py\n' \
    >"$tmp/surface/fixtures/wheel-entries.txt"
  printf '{"releases": {"0.10.0": []}}\n' >"$tmp/surface/fixtures/pypi.json"
  printf '{"versions": {"0.10.0": {}}}\n' >"$tmp/surface/fixtures/npm.json"
  printf '{"num": "0.10.0"}\n' >"$tmp/surface/fixtures/crates.json"
  printf '<metadata><versioning><versions><version>0.10.0</version></versions></versioning></metadata>\n' \
    >"$tmp/surface/fixtures/maven.xml"
  if out="$(TREE="$tmp/surface" FIXTURES="$tmp/surface/fixtures" verify_published 2>&1)"; then
    echo "❌ self-test: a wheel without binding/ passed the published check"; failures=$((failures + 1))
  else
    case "$out" in *"carries no rigorix_verifier/binding/"*) : ;;
      *) echo "❌ self-test: the surface refusal did not name the missing package"; printf '%s\n' "$out" | tail -2; failures=$((failures + 1)) ;; esac
  fi

  if [ "$failures" -gt 0 ]; then
    echo "❌ check-release self-test: $failures case(s) wrong"
    return 1
  fi
  echo "✅ check-release self-test: a published version and a disagreeing tag are refused by name, a split manifest and a wheel without binding/ too, and a clean release passes"
  return 0
}

case "$MODE" in
  self-test) self_test; exit $? ;;
  verify) verify_published ;;
  *) preflight ;;
esac