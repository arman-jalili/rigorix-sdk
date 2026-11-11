# Releasing the SDK

One version for the verifier's **lockstep channels**: crates.io `rigorix-verifier`, npm
`rigorix-verifier`, PyPI, and Maven Central. `rigorix-schemas`, `rigorix-client` and the npm client
are an independent cadence: they carry the workspace version and must stay pin-consistent, but a
verifier patch does not force a schema/client release. `.pi/scripts/validate-channel-versions.sh`
fails the build when the verifier channels disagree, when a required manifest is missing, or when
an intra-workspace pin does not match the workspace version. Its `--self-test` seeds the drift this
repo actually shipped: the Java artifact at `0.2.0`, the #57 three-behind npm verifier, and a stale
PyPI `__version__`.

| channel | artifact | how it publishes | auth | tag |
|---|---|---|---|---|
| **crates.io** | `rigorix-schemas`, `rigorix-verifier` | manual `cargo publish`, schemas **first and indexed** | `$CRATES_TOKEN` | `rust-vX.Y.Z` |
| **npm** | `rigorix-verifier`, `rigorix-client` | `npm publish --access public` (CI job, or manually) | `NPM_TOKEN` | `vX.Y.Z` |
| **PyPI** | `rigorix-verifier` | CI job, **Trusted Publishing (OIDC)** — no long-lived token exists | — | `vX.Y.Z` |
| **Maven Central** | `eu.rigorix:rigorix-verifier` | CI job, `mvn -Prelease deploy` (sources + javadoc + GPG) | `MAVEN_CENTRAL_USERNAME` / `_TOKEN`, `MAVEN_GPG_PRIVATE_KEY` / `_PASSPHRASE` | `vX.Y.Z` |
| **Go** | `github.com/arman-jalili/rigorix-sdk/go` | **tag only** — nothing is uploaded | public repo visibility | `go/vX.Y.Z` |

`rigorix-client` (Rust) is an independent cadence: bumped with the train, published separately.

**Lockstep set:** crates.io `rigorix-verifier`, npm `rigorix-verifier`, PyPI, Maven Central. The
schema/client crates are reported by the guard but not locked to the verifier version; their
`rigorix-schemas` pins must match the workspace version. The verifier exact-pins
`rigorix-schemas` (`=X.Y.Z`), which is the one place the two cadences touch — publish the schema
first, or Cargo refuses the verifier.

## Order

Six steps, in the order the gate permits. **The order is load-bearing because each step
has a check that refuses the next one done early** — that is what makes it worth writing
down once, here, instead of in three places that drift.

The order recorded here used to put the crates first, which makes the release impossible:
`publish.yml`'s preflight runs `check-release.sh --tag`, and *that* refuses when any
channel already serves the version (`❌ published channel(s) already serve X.Y.Z — a
version means released content`). The order that actually produced 0.10.0 is the one
below.

### 1. State the new version in the documents that declare it

```sh
# every (channel, document) pair the release gate checks
cat docs/published-versions.tsv
bash scripts/check-release.sh --verify-docs --expect X.Y.Z   # exits 1 until they agree
```

*Gate:* `--verify-docs --expect <version>`, run by the preflight **before** any upload,
reading no registry — before the upload, a registry can only answer with the previous
version (#125). A stale document stops the release; it is not discovered afterwards.

### 2. Tag `vX.Y.Z`

```sh
git tag -a vX.Y.Z -m "X.Y.Z" && git push origin vX.Y.Z
```

*Gate:* the preflight's `check-release.sh --tag vX.Y.Z` — one version across the four
manifests, an annotated tag whose commit is that version, and nothing serving it yet. The
push publishes npm `rigorix-verifier`, PyPI and Maven Central.

### 3. Tag `go/vX.Y.Z`

```sh
git tag -a go/vX.Y.Z -m "X.Y.Z" && git push origin go/vX.Y.Z
```

*Gate:* `check-release.sh --verify-published --channels go` opens the proxy's zip and
requires `gate/` and the pinned artifact. A root `vX.Y.Z` tag does **not** version a
module in `go/`, so step 2 does nothing for Go.

### 4. Verify the three channels this workflow publishes

```sh
bash scripts/check-release.sh --verify-published --channels pypi,npm,maven
```

The workflow does this itself in `verify-published` (exit 3 there is a pass *for that
question only*: the set is complete for what it uploads). Run it by hand when debugging a
red run; `complete: 3 of 3 verified (asked: …)` is the line to look for.

### 5. Publish the crates **after** the tag — schema first, by hand

```sh
cargo publish -p rigorix-schemas --token "$CRATES_TOKEN"
# wait for the index to serve it, then:
cargo publish -p rigorix-verifier --token "$CRATES_TOKEN"
```

*Why last, and why this order:* the verifier exact-pins `rigorix-schemas` (`=X.Y.Z`), so
`rigorix-verifier` cannot be published before the schema it pins is indexed. And it is
after the tag because the preflight refuses a version any channel already serves — the
old runbook had these two facts in the opposite order, which made step 2 unreachable.

No `v`-tag publishes the crates: `rust-vX.Y.Z` (step 6) is a marker, and the marker
triggers nothing. This is the step that keeps 0.10.0 at three of four channels for a day.

### 6. Mark the crates, then ask the complete question

```sh
git tag -a rust-vX.Y.Z -m "X.Y.Z" && git push origin rust-vX.Y.Z
gh workflow run publish.yml -f tag=vX.Y.Z -f channels=crates,pypi,npm,maven,go
```

*Gate:* the dispatch's `verify-published` asks all five. A dispatch with **no** `channels`
input asks all five too — a partial answer to the default question fails the job (#134);
narrowing it with `-f channels=…` is a deliberate act and reports a warning instead.

The npm **client** (`typescript-client`) travels on its own tag, `client-vX.Y.Z`, and is
not part of this sequence at all: no verifier tag publishes it, and no verifier tag fails
on it.

## Why the order is load-bearing

The verifier's correctness is defined against the schema it was built with. Publishing the verifier
before the schema it pins publishes two artifacts that do not agree, and the failure surfaces later
as a verification result nobody can reproduce.

## "Published" means consumable, not uploaded

Each channel is confirmed by resolving the artifact from the registry, not by reading a green job:

```sh
cargo add rigorix-verifier@X.Y.Z --dry-run     # or a scratch crate that builds
npm view rigorix-verifier version
pip index versions rigorix-verifier
# Maven: the coordinate's own metadata, never a directory URL. Central serves no
# listings, so .../X.Y.Z/ answers 404 for a version that is fully published — asking
# it produced a false "the channel is not live" on 0.9.0.
curl -s https://repo1.maven.org/maven2/eu/rigorix/rigorix-verifier/maven-metadata.xml | grep '<release>'
curl -sI https://repo1.maven.org/maven2/eu/rigorix/rigorix-verifier/X.Y.Z/rigorix-verifier-X.Y.Z.jar
go get github.com/arman-jalili/rigorix-sdk/go@vX.Y.Z
```

A job that uploads and a version that resolves are different claims. The Maven job sets
`<waitUntil>published</waitUntil>` for exactly this reason, and the publish workflow's `smoke` job
installs from the registries afterwards.

## Known blockers (recorded, not discovered)

- **GitHub Actions billing.** Every workflow in this repository starts no steps when the account's
  spending limit is reached, which looks like a normal red workflow and publishes nothing. PyPI
  cannot be published any other way (OIDC only), so a `vX.Y.Z` tag is *staged*, not released, until
  billing is restored — then re-run the failed publish run rather than re-tagging.
- **Maven Central is configured and publishing.** Recorded because getting here cost a detour worth not
  repeating: the namespace `eu.rigorix` (domain `rigorix.eu`) verifies with a TXT record at the **apex**,
  `rigorix.eu` — a record on a subdomain such as `maven.rigorix.eu` fails with *"Verification result could
  not be found"*, which reads like a propagation problem and is not one. The signing key
  `CA59BA9B24180611F16DC829D78D7E6E67BBCAFF` (Rigorix Releases, RSA 4096, expires 2028-10-24) is published
  to keys.openpgp.org, whose UID must be reachable at `release@rigorix.eu` or the key is uploaded but never
  served. A deployment id (for example `9727d513`) is the first successful one; artifacts appear under
  `repo1.maven.org/maven2/eu/rigorix/`.
- **Go needs repository visibility.** `go get` reads the repo through the module proxy, which cannot
  see a private repository. A `go/vX.Y.Z` tag on a private repo is a correct release of nothing
  consumable.

## When a channel says no

Four answers that each look like a verdict and are not, each paid for once:

- **`401 Invalid request` from the Central Portal is not a token verdict.** `setup-java` writes
  `${env.MAVEN_CENTRAL_USERNAME}` and `${env.MAVEN_CENTRAL_TOKEN}` into `settings.xml`; a deploy step that
  exports only the GPG passphrase sends *empty* credentials, and the Portal answers `401` exactly as it
  would for a revoked token. Both must be exported to the step that runs `mvn deploy`. The second cause is
  different again and only visible once the first is fixed: a valid token from an account without publish
  rights answers `Namespace 'eu.rigorix' is not allowed`.
- **A `404` on a directory is not an absent artifact.** Central serves no listings. Ask for
  `maven-metadata.xml`, and for the `.pom` and `.jar` themselves.
- **A replay that fails `400 File already exists` is a missing skip, not a broken release.** Every publish
  step must query the index first and treat "already there" as success, or the re-run that fixes one
  channel fails on the five that were fine.
- **A green job is not a consumable version.** Hence the `smoke` job: it installs from the registries after
  the publish job reports success.

And one from the OSS train the same day: **a workflow job that has never executed is not a job that works.**
The npm publication step had been wired for two releases and skipped both times; on its first real run it
failed in 0.2 s on a toolchain prerequisite nothing had ever needed to notice.
