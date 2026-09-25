## Summary

Delivers Strategy A's cross-language claim (D-2): **independent** Python and
TypeScript verifiers that reproduce the Rust verifier's proofs **byte-exact**,
proven against the **same** committed engine fixtures. A Python/Node consumer
can now check an envelope HMAC, JSON Schema conformance, an ADR-016 chain, and
the Ed25519 anchor artifacts without shelling out to Rust.

Closes #21. **Stacked on #20** (base branch `issue/20`).

## Canonical form (the hard part)

`serde_json::to_string(envelope with signature=None)`: struct field order,
`skip_serializing_if` omissions, non-skipped `Option` as `null`, sorted
`scoring_results`/`dimensions` maps, and sorted `serde_json::Value` payload
keys. Field order is read from `schemas/envelope.json`.

- **Python**: stdlib `json.dumps(separators=(",",":"), ensure_ascii=False)`.
- **TypeScript**: `lossless-json` preserves number lexemes (`1.0` stays `1.0`)
  — `JSON.stringify` would emit `1` and break the HMAC.

## Changes

**`python/`** — `rigorix_verifier` package: `canonical`, `envelope`
(HMAC + `jsonschema`), `chain` (incl. checkpoint-covered gaps), `anchor`
(Ed25519 via `cryptography`), `corpus`; `pyproject.toml`; README; `_schemas`
symlink. Tests in `python/tests/`.

**`typescript/`** — same surface: `canonical`, `envelope` (`ajv` +
`ajv-formats`), `chain`, `anchor` (Ed25519 via `node:crypto`), `corpus`;
`package.json`, `tsconfig.json`, README; `_schemas` symlink. Tests in
`typescript/test/` via `node --test`.

**CI** — `.github/workflows/ci.yml` gains `python-verifier` (pytest) and
`typescript-verifier` (npm ci + npm test) jobs. `.gitignore` ignores
`typescript/dist/`.

## Verification

```
# Python
cd python && pytest -q                      # 16 passed

# TypeScript
cd typescript && npm ci && npm test         # 16 passed (tsc + node --test)

# Rust unchanged
cd rust && cargo test --workspace           # 25 passed (+1 ignored)
```

Both suites cover: byte-exact HMAC on every signed engine fixture, tamper
rejection, unsigned-must-be-degraded, wrong-status-case schema rejection,
valid/broken/altered/duplicate chains, checkpoint-covered gap acceptance,
forged-checkpoint rejection, and receipt/slice/checkpoint Ed25519 verification
+ tamper rejection.

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Python byte-exact on the committed fixtures | ✅ 16 tests |
| 2 | TypeScript byte-exact, same fixtures | ✅ 16 tests |
| 3 | Negative tests (tamper, broken chain, bad sig) | ✅ both |
| 4 | No repo-relative corpus dependency | ✅ env → bundled `_schemas` |
| 5 | CI green per language | ✅ new jobs |

## Out of scope

- Typed API clients (SDK-C4 / #11).
- Java/Go verifiers (follow-ups).
- Any rigorix-engine/execution logic (D-1).
