# Releasing the SDK

One version, five publication channels. The version lives in six manifests and
`.pi/scripts/validate-channel-versions.sh` fails the build when they disagree — it also has a
`--self-test` that seeds the drift this repo actually shipped (the Java artifact sat at `0.2.0`
while every other channel was at `0.6.0`, and nothing noticed).

| channel | artifact | how it publishes | auth | tag |
|---|---|---|---|---|
| **crates.io** | `rigorix-schemas`, `rigorix-verifier` | manual `cargo publish`, schemas **first and indexed** | `$CRATES_TOKEN` | `rust-vX.Y.Z` |
| **npm** | `rigorix-verifier`, `rigorix-client` | `npm publish --access public` (CI job, or manually) | `NPM_TOKEN` | `vX.Y.Z` |
| **PyPI** | `rigorix-verifier` | CI job, **Trusted Publishing (OIDC)** — no long-lived token exists | — | `vX.Y.Z` |
| **Maven Central** | `dev.rigorix:rigorix-verifier` | CI job, `mvn -Prelease deploy` (sources + javadoc + GPG) | `MAVEN_CENTRAL_USERNAME` / `_TOKEN`, `MAVEN_GPG_PRIVATE_KEY` / `_PASSPHRASE` | `vX.Y.Z` |
| **Go** | `github.com/arman-jalili/rigorix-sdk/go` | **tag only** — nothing is uploaded | public repo visibility | `go/vX.Y.Z` |

`rigorix-client` (Rust) is an independent cadence: bumped with the train, published separately.

## Order

1. `crates.io`: `rigorix-schemas`, then wait for it to be indexed, then `rigorix-verifier`
   (its dependency resolves against the new version).
2. Tag `vX.Y.Z` → npm, PyPI and Maven Central.
3. Tag `go/vX.Y.Z` for the Go module (a root `vX.Y.Z` tag does **not** version a module in `go/`).
4. `rust-vX.Y.Z` marker tag for the crates.

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
# https://repo1.maven.org/maven2/dev/rigorix/rigorix-verifier/X.Y.Z/
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
- **Maven Central needs a namespace and a signing key.** `dev.rigorix` must be verified on the
  Central Portal, and the GPG key must be published. The CI job fails by name when a secret is
  missing rather than skipping: a tag that reaches three registries of five is the drift the version
  guard exists to prevent.
- **Go needs repository visibility.** `go get` reads the repo through the module proxy, which cannot
  see a private repository. A `go/vX.Y.Z` tag on a private repo is a correct release of nothing
  consumable.
