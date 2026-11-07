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

1. `crates.io`: `rigorix-schemas`, then wait for it to be indexed, then `rigorix-verifier`
   (its dependency resolves against the new version).
2. Tag `vX.Y.Z` → npm, PyPI and Maven Central.
3. Tag `go/vX.Y.Z` for the Go module (a root `vX.Y.Z` tag does **not** version a module in `go/`).
4. `rust-vX.Y.Z` marker tag for the crates.
5. The npm **client** (`typescript-client`) has its own tag: `client-vX.Y.Z`. A verifier tag
   (`vX.Y.Z`) does not publish it, and does not fail on it either — the two cadences are
   independent, and the workflow checks each against the tag that names it.

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
  served. Deployment ids `9727d513` (0.8.0) is the first successful one; artifacts appear under
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
