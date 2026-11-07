## Summary

Closes #59. `rigorix-verifier@0.9.0` cannot be imported by a page: every entry
reaches for `node:crypto`, `node:module`, `node:fs`, `node:path`, or `node:url`.
This adds a second entry, `rigorix-verifier/browser`, with **no Node imports**,
backed by the platform's WebCrypto.

## Two entries, one package

| Entry | Runtime | Crypto | Corpus |
|---|---|---|---|
| `.` (unchanged) | Node | `node:crypto` | `_schemas` (fs) |
| `./browser` | page | `crypto.subtle` | generated string constants |

The browser entry exports `canonicalBytes`, `envelopeHash`, `verifySignature`,
`verifyChain`, `verifyChainWithCheckpoints`, `verifyLedgerReceipt`,
`verifyHistorySlice`, `verifyCompactionCheckpoint`, `validateEnvelope`, and
`validateSchema`. Async where WebCrypto is async; `canonicalBytes` returns
`Uint8Array` (Node returns `Buffer`).

## How

- **Shared pure cores**: `canonical-core.ts` (byte rules + field iteration, caller
  supplies the order) and `schema-core.ts` (Ajv over a pluggable corpus). The
  Node entry keeps its `Buffer`/`createHmac`/`createRequire` path; the browser
  entry wraps the same JSON in `TextEncoder` and uses `crypto.subtle`.
- **WebCrypto**: HMAC-SHA256 via `importKey`/`sign`, SHA-256 via
  `crypto.subtle.digest`, Ed25519 via `importKey("spki")`/`verify`. Signatures are
  compared over raw bytes, constant-time — not `===` on hex strings.
- **Corpus**: `scripts/bundle-schemas.mjs` also emits
  `src/browser/corpus.generated.ts` (canonical schemas, fixtures excluded), so a
  page has no filesystem dependency.
- **Guard**: `scripts/check-browser-no-node.mjs` runs after `tsc` and fails the
  build if anything under `dist/src/browser/**` contains `node:`.
- **Test**: `test/browser/run.mjs` esbuild-bundles the emitted entry, serves it,
  and runs it in **real Chrome** via `playwright-core`; every verdict is compared
  with the Node entry.

No polyfill: a `crypto-browserify` shim would make the MAC depend on an
unaudited implementation. The page uses the platform's own crypto.

## Verification

```
npm run build                                ✅ guard: 0 node: hits
grep -rn 'node:' dist/src/browser/           ✅ 0 hits
npm run test:node                            ✅ 20 tests (Node unchanged)
npm run test:browser                         ✅ real Chrome, all verdicts equal Node
  S1 payload byte flipped                    ✅ SignatureMismatch (both)
  S2 key differs by one byte                 ✅ SignatureMismatch (both)
  S3 seed `import "node:fs"`                 ✅ build fails, names corpus.js/.d.ts
npm pack --dry-run                           ✅ browser entry + generated corpus shipped
rust 34 / python 20 / go / java              ✅
validators                                   ✅
```

`test:browser` is now a CI step in `typescript-verifier` (real Chrome on
`ubuntu-latest`), so a Node import or a cross-entry divergence cannot land
silently.

## Acceptance

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `.` unchanged and green | ✅ |
| 2 | `./browser` has no `node:` imports | ✅ guard + raw grep |
| 3 | Same canonical bytes / verdicts | ✅ |
| 4 | S1 tampered payload rejects in both | ✅ |
| 5 | S2 one-byte key difference rejects in both | ✅ |
| 6 | S3 build guard names the offending file | ✅ seed proven |
| 7 | No polyfill | ✅ WebCrypto only |

## Not in this PR

#57 remains open: Maven Central still reports `release: 0.8.0` and `0.9.0/` is
404, so the Java channel is not discoverable at 0.9.0. That is a Central
credential refresh, not a code change.
