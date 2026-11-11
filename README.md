# rigorix-sdk

Contract-first SDK + integration surface for Rigorix. **Not a crate inside rigorix-oss** —
a standalone repo whose job is to make the Rigorix boundary speakable from any stack.

## What lives here

| Path | Purpose |
|------|---------|
| `schemas/` | **Single source of truth** for Rigorix contracts: envelope v2, policy/config model, identity claim format, native `rigorix.*` API method catalog. Drift-tested against rigorix-oss (CI). |
| `rust/` | `rigorix-schemas` + `rigorix-verifier` (in-tree **0.10.0**; **0.9.0** published) + `rigorix-client` — typed JSON-RPC client + envelope/chain/anchor verifier (protocol-only, **no** `rigorix-engine` dependency) |
| `python/` · `typescript/` · `java/` · `go/` | The same verifier + catalog client, byte-exact on the shared fixtures (`rigorix-verifier` on PyPI/npm; Maven `eu.rigorix:rigorix-verifier`; Go module) |
| `docs/` | Contract-sync design notes and ADRs |

## Direction

- **Verification first (now):** schemas + envelope verifiers so the HMAC-signed audit
  trail is independently checkable in any CI and any language. A signature only its own
  tools can check is self-referential.
- **Server mode (next):** one native `rigorix.*` JSON-RPC catalog, frozen here, served by
  a reference implementation and by any other implementation that adopts it. SDK clients
  are thin typed wrappers over that catalog.
- SSE: legacy MCP SSE stays removed (GAP-A-10). What returns is HTTP JSON-RPC plus an
  SSE push channel on the **native** contract (approvals, progress); MCP Streamable HTTP
  is optional later for GUI agents.
- Sequence: **contract sync → catalog design → implementation that serves it → SDK clients.**

## Governance invariant

Every SDK exposes **governed flows only** (plan → enforce → approve → run → audit) — no
direct-execute escape hatch. Embedded governance is Rust-only, via `rigorix-engine` on
crates.io, documented as a separate path. This repo is itself intended to be
rigorix-governed once v0 lands (dogfood demo #2).

## Status

- [x] Repo scaffold + contract direction (2026-09-06)
- [x] Contract-sync design doc (2026-09-06) — enterprise-side situation file created
- [x] Envelope v2 schema + signed fixtures (anchored / effect-key / sequence-denied / unsigned-degraded)
- [x] Policy/config model schema (`policy.json`) + identity/claim schema (`claims.json`)
- [x] Catalog freeze — ADR-0001, **24** `rigorix.*` methods (OSS server serves a 19-method subset) — drift CI in both OSS and enterprise
- [x] ADR-017 / consequence-gating §4.3 — `rigorix.audit.authorityFacts` + `api/authority-fact-bundle.json` (SDK #44)
- [x] SSE push channel — ADR-0002 + `events.json` + fixtures
- [x] ADR-016 integrity contract — `api/history-slice.json`, `api/ledger-receipt.json`, `api/compaction-checkpoint.json`
- [x] **0.10.0** — the release that carries the in-process gate. The tree, the three
  tags (`v0.10.0`, `go/v0.10.0`, `rust-v0.10.0`) and every channel agree, and
  `bash scripts/check-release.sh --verify-published` proves it against the registries
  rather than against the tree (see [docs/publication-readiness.md](docs/publication-readiness.md)).

What each coordinate serves is stated **once**, below. The prose elsewhere says "the
published version" rather than repeating a number that a release moves:
`bash scripts/check-release.sh --verify-docs` fails when a document here disagrees with
the channel it describes.

<!-- published: crates=0.10.0 pypi=0.10.0 npm=0.10.0 maven=0.10.0 go=0.10.0 -->

| channel | coordinate | published | carries the in-process gate |
|---|---|---|---|
| crates.io | `rigorix-schemas`, `rigorix-verifier` | the published version | — verifier core; the gate ships in the Python and Go packages |
| PyPI | `rigorix-verifier` | the published version | **yes** — `rigorix_verifier.binding` and a vendored `rigorix_gate_wasi.wasm` |
| npm | `rigorix-verifier` | the published version | no (the package claims no binding) |
| npm | `rigorix-client` | 0.8.0 | independent cadence, by design |
| Maven Central | `eu.rigorix:rigorix-verifier` | the published version | no (by design) |
| Go module proxy | `…/rigorix-sdk/go` | the published version | **yes** — `go/gate/`, same vendored artifact |
- [x] Python / TypeScript / Java / Go verifiers + catalog clients — fixtures green in each language

*Last verified: 2026-11-11 against `rigorix-oss` `v1.14.3` (the gate artifact the
vendored copies hash to) and against every channel above, by
`scripts/check-release.sh --verify-published` and `--verify-docs`.*

## Development

```bash
bash .ci/local-ci.sh     # every CI job plus the seven validators, no secret needed
```

The runner prints how many steps it executed and exits `1` on a failure, `3` when
a step was skipped for lack of a subject (the Python binding tests need Linux or
Docker: wasmtime's JIT is killed by the macOS sandbox).

- **Contributing:** [CONTRIBUTING.md](CONTRIBUTING.md) — the
  [Contributor Licence Agreement](docs/CLA.md) a contribution is made under, and
  the rules this repository holds itself to.
- **Publication readiness:** [docs/publication-readiness.md](docs/publication-readiness.md)
  — including the recorded decision to publish the history as it stands.
- **Security:** [SECURITY.md](SECURITY.md) — private reporting, and who answers a
  wasm-engine advisory.

## Licence

**Apache-2.0**, and only Apache-2.0. The full text is [LICENSE](LICENSE) and the
attribution statement is [NOTICE](NOTICE). Every published source file states it in
its own header, and the claim is measured rather than listed by hand:

```bash
bash scripts/check-spdx.sh   # 44 file(s) carry SPDX-License-Identifier: Apache-2.0
```

The manifests (`rust/Cargo.toml`, both `package.json` files, `python/pyproject.toml`,
`java/pom.xml`) declare it too; a Go module has no field for it and inherits the
repository `LICENSE`.

The licence grants no trademark rights (Apache-2.0 §6): what the names permit is
stated in [TRADEMARK.md](TRADEMARK.md).

The Apache licence rather than MIT because it carries an express patent grant,
which matters for a verifier others embed. The schemas under `schemas/` are part of
this repository and covered by the same licence; they carry no per-file licence
field, deliberately — adding one would change the bytes of a frozen contract that
other repositories pin, so the terms are stated here and in
[schemas/README.md](schemas/README.md).
