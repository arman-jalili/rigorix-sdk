# Releasing the SDK

Two distribution channels share one version (`0.2.0`):

- **Rust crates (crates.io)** — `rigorix-schemas`, `rigorix-verifier`
  (`rigorix-client` is a typed protocol client, independent cadence). Published
  manually (`cargo publish`), marker tag `rust-v0.2.0`.
- **Python + TypeScript (PyPI + npm)** — `rigorix-verifier` (both) and
  `rigorix-client` (npm). Published by CI on the `v0.2.0` tag.

`rust/Cargo.toml` `[workspace.package] version` is the single source for every
workspace member (`version.workspace = true`). The verifier + client pin
`rigorix-schemas` to the **same exact version**, and `rigorix-schemas` must be
published **before** the verifier.

## 0.2.0 — required for anchored verification

`0.1.0` predates the ADR-016 Phase C `anchor_head`, so a 0.1.0 verifier **cannot
verify an anchored envelope** (it drops the field when computing canonical
bytes). `0.2.0` is the anchored-verification release. Do **not** yank 0.1.0 — it
stays valid for catalog-only / unanchored use.

### 1. Prove the artifacts locally

```bash
cd rust && ./scripts/verify-packaged-crates.sh
```

Gate 1: the packaged `rigorix-schemas` `.crate` carries `schemas/envelope.json`
with `anchor_head` + the anchored fixture. Gate 2: a clean scratch consumer
verifies `envelope-anchored-signed.json` byte-exact with `RIGORIX_SDK_SCHEMAS`
**unset**.

### 2. Publish (needs a crates.io token; clean `main`)

Order matters — the verifier's dep is exact-versioned:

```bash
cargo publish -p rigorix-schemas
cargo publish -p rigorix-verifier
```

After `rigorix-schemas` 0.2.0 is live, the previously-deferred
`cargo package -p rigorix-verifier` / `cargo publish --dry-run` become runnable.

### 3. Verify from a clean scratch project

Never the workspace path (a path dep would mask a packaging bug):

```bash
cargo new /tmp/rigorix-verify-0.2.0 && cd /tmp/rigorix-verify-0.2.0
cargo add rigorix-verifier@0.2.0
# run a main that verifies envelope-anchored-signed.json with the env unset
```

### 4. Tag

Two tags, two purposes — both point at the same commit on `main`:

- **`rust-v0.2.0`** — the Rust crates marker. Does **not** trigger any workflow
  (the crates are published manually above).
- **`v0.2.0`** — triggers `.github/workflows/publish.yml`, which publishes the
  Python + TypeScript artifacts to **PyPI** and **npm**. The workflow asserts the
  tag matches each package version (`v0.2.0` → `0.2.0`), so the tag is load-bearing.

```bash
git tag rust-v0.2.0 && git push origin rust-v0.2.0   # crates marker
git tag v0.2.0     && git push origin v0.2.0         # → PyPI + npm publish
```

> `publish.yml` matches `tags: ["v*"]`. `rust-v0.2.0` deliberately does **not**
> match (it starts with `r`) — pushing only `rust-v0.2.0` publishes the crates and
> silently skips PyPI/npm. Push **both** tags.

### 5. Bump consumers (0.x semver: `^0.1` does **not** match `0.2`)

- `rigorix-oss/server/Cargo.toml` → `rigorix-verifier = "0.2"`
- `rigorix-enterprise/core/Cargo.toml` → `rigorix-verifier = "0.2"`

Then run their CI. The bump is mandatory: `^0.1` will not resolve 0.2.0.
