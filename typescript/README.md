# rigorix-verifier (TypeScript)

Strategy A parity for the Rigorix signed audit trail: an **independent,
protocol-only** verifier for Node. No engine dependency.

- **HMAC-SHA256** over the canonical form (`signature` nulled) — byte-exact
  with the rigorix-oss engine and the Rust verifier.
- **JSON Schema** conformance (draft 2020-12 via `ajv`).
- **ADR-016 chains**: per-producer sequence + `prev_hash` continuity, gaps
  accepted only when covered by a valid signed compaction checkpoint.
- **Ed25519 anchor artifacts** (`node:crypto`): ledger receipt, history slice,
  compaction checkpoint.

## Install

```bash
npm install rigorix-verifier@0.2.0   # published artifact (embedded corpus)
npm install && npm run build          # from source
```

## Usage

```ts
import { readFileSync } from "node:fs";
import { parse } from "lossless-json";
import { verifyChain, verifySignature, validateEnvelope } from "rigorix-verifier";

const text = readFileSync("envelope.json", "utf8");
verifySignature(text, "fixture-hmac-key-2026"); // byte-exact HMAC
validateEnvelope(JSON.parse(text));             // schema conformance

const chain = parse(readFileSync("chain.json", "utf8")) as any;
verifyChain(chain);                              // ADR-016 local chain
```

## Canonical form

The HMAC is over `serde_json::to_string(envelope with signature=None)` as the
engine emits it: **struct field order**, `skip_serializing_if` fields omitted
when `null`/empty, non-skipped `Option` fields as `null`, `scoring_results` and
its `dimensions` maps sorted, and payloads with sorted keys. The field order is
read from `schemas/envelope.json`.

`lossless-json` is used instead of `JSON.parse`/`JSON.stringify` so number
lexemes survive (`1.0` stays `1.0`; JS would emit `1`, breaking the HMAC). The
committed engine fixtures prove byte-exact parity (`test/envelope.test.ts`).

## Contract corpus

Resolution (mirrors the Rust verifier):

1. `RIGORIX_SDK_SCHEMAS` — an explicit external corpus (CI/local override).
2. The bundled `_schemas` directory.

The bundled copy is **generated** from the repo-root `schemas/` (the single
source of truth) by [`scripts/bundle-schemas.mjs`](scripts/bundle-schemas.mjs):
npm `prepack`/`build` run it before packing. It is a real directory (npm will
**not** dereference a symlink into the tarball), never a committed duplicate;
`test/corpus-sync.test.ts` fails if it drifts from the canonical corpus. The
pack gate (`npm pack` → install the tarball into a clean project → verify with
`RIGORIX_SDK_SCHEMAS` unset) runs in CI.

## Test

```bash
npm test          # tsc + node --test
```
