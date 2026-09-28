# Releasing the SDK crates

Published crates: **`rigorix-schemas`** and **`rigorix-verifier`**.
`rigorix-client` is a typed protocol client (independent release cadence).

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

```bash
git tag rust-v0.2.0 && git push origin rust-v0.2.0
```

### 5. Bump consumers (0.x semver: `^0.1` does **not** match `0.2`)

- `rigorix-oss/server/Cargo.toml` → `rigorix-verifier = "0.2"`
- `rigorix-enterprise/core/Cargo.toml` → `rigorix-verifier = "0.2"`

Then run their CI. The bump is mandatory: `^0.1` will not resolve 0.2.0.
