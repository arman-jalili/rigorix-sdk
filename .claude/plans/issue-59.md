# Implementation Plan: issue/59

**Branch:** `issue/59`
**Base:** `main` (`63575ec`)
**Issue:** #59 — browser entry: same canonical bytes, WebCrypto, no Node imports
**Severity:** high — blocks a private downstream workstream (#33): the public demo cannot verify a receipt

## Status

- [x] Pure canonical + schema cores (no Node imports)
- [x] Browser entry with WebCrypto HMAC/SHA-256/Ed25519
- [x] Generated browser schema corpus + `node:` build guard
- [x] `./browser` package export, scripts, CI step
- [x] Real-Chrome conformance vs the Node entry (S1/S2)
- [x] S3 guard seed proven
- [ ] MR created
- [ ] Merged

## End state

Two entries, one package, unchanged Node API:

| Entry | Runtime | Crypto | Corpus |
|---|---|---|---|
| `.` | Node | `node:crypto` | `_schemas` (fs) |
| `./browser` | page | `crypto.subtle` | generated string constants |

The browser entry exports `canonicalBytes`, `envelopeHash`, `verifySignature`,
`verifyChain`, `verifyChainWithCheckpoints`, `verifyLedgerReceipt`,
`verifyHistorySlice`, `verifyCompactionCheckpoint`, `validateEnvelope`, and
`validateSchema`. It is async where the platform crypto is async; `canonicalBytes`
returns `Uint8Array` (the Node entry returns `Buffer`).

## Design

- `src/canonical-core.ts` — the byte rules and field iteration, pure; the caller
  supplies an `OrderResolver`. Node wraps the JSON in `Buffer`; the browser wraps
  it in `TextEncoder`.
- `src/schema-core.ts` — Ajv setup over a `SchemaCorpus`; Node loads
  `ajv-formats` with `createRequire`, the browser with a static import.
- `src/browser/webcrypto.ts` — `importKey`/`sign`/`digest`/`verify`, hex
  helpers, and a constant-time byte comparison (not `===` over hex strings).
- `src/browser/corpus.ts` — reads `corpus.generated.ts`, emitted by
  `scripts/bundle-schemas.mjs` from the canonical schemas (fixtures excluded).
- `scripts/check-browser-no-node.mjs` — runs after `tsc`; fails if anything under
  `dist/src/browser/**` contains `node:`.
- `test/browser/run.mjs` — esbuild-bundles the emitted entry, serves it, and runs
  it in real Chrome via `playwright-core`; compares every verdict with Node.

No polyfill: a bundler shim would make the MAC depend on an unaudited
implementation. The page uses the platform's own crypto.

## Verification

```
npm run build                                ✅ guard: 0 node: hits
grep -rn 'node:' dist/src/browser/           ✅ 0 hits
npm run test:node                            ✅ 20 tests
npm run test:browser                         ✅ real Chrome; every verdict equals Node
  S1 payload byte flipped                    ✅ SignatureMismatch (both)
  S2 key differs by one byte                 ✅ SignatureMismatch (both)
  S3 seed `import "node:fs"` in corpus.ts    ✅ build fails, names corpus.js/.d.ts
npm pack --dry-run                           ✅ browser entry + generated corpus shipped
rust 34 / python 20 / go / java              ✅
validators (ci/tests/security/operations/canonical/architecture/integration) ✅
```

## Acceptance

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `.` unchanged and green | ✅ 20 Node tests |
| 2 | `./browser` has no `node:` imports | ✅ guard + raw grep |
| 3 | Same canonical bytes / verdicts | ✅ cross-entry test |
| 4 | S1 tampered payload rejects in both | ✅ |
| 5 | S2 one-byte key difference rejects in both | ✅ |
| 6 | S3 build guard names the offending file | ✅ seed proven |
| 7 | No polyfill | ✅ WebCrypto only |

## Note on #57

Still open: Maven Central reports `release: 0.8.0` and `0.9.0/` is 404, so the
Java channel is not discoverable at 0.9.0. That is a Central credential refresh,
not a code change; this PR does not touch it.
