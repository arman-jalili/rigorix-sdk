# Implementation Plan: issue/21

**Branch:** `issue/21` (stacked on `issue/20`)
**Base:** `issue/20` → `main` after the stack merges
**Issue:** #21 — SDK-C6: multi-language verifiers (Python + TypeScript)

## Classification

New deliverables (two language packages). Scope: **Critical** (independent
re-implementation of the trust primitive).

## Approach

Independent, protocol-only verifiers that reproduce the **same** proofs as the
Rust verifier byte-exact, proven against the **same** committed fixtures. No
shelling out to Rust; no engine dependency (D-1).

## The hard part — canonical bytes (solved)

`serde_json::to_string(envelope with signature=None)`: struct field order,
`skip_serializing_if` omissions, non-skipped `Option` as `null`, sorted
`scoring_results`/`dimensions`, sorted `serde_json::Value` payload keys.
Validated against all signed engine fixtures before implementation.

- **Python**: field order read from `schemas/envelope.json`; stdlib
  `json.dumps(separators=(",",":"), ensure_ascii=False)`.
- **TypeScript**: same, but `lossless-json` preserves number lexemes (`1.0`
  stays `1.0` — `JSON.stringify` would emit `1` and break the HMAC).

## Deliverables

1. `python/` — `rigorix_verifier` package: `canonical`, `envelope` (HMAC +
   `jsonschema`), `chain`, `anchor` (Ed25519 via `cryptography`), `corpus`;
   `pyproject.toml`, README; corpus via `RIGORIX_SDK_SCHEMAS` →
   bundled `_schemas` (symlink).
2. `typescript/` — same surface: `canonical`, `envelope` (`ajv` + `ajv-formats`),
   `chain`, `anchor` (Ed25519 via `node:crypto`), `corpus`; `package.json`,
   `tsconfig.json`, README; `node --test`.
3. CI jobs for Python (`pytest`) and TypeScript (`npm ci && npm test`).

## Validation

- [x] Python `pytest` — **16 passed** (parity + negatives)
- [x] TypeScript `npm test` (tsc + `node --test`) — **16 passed** (parity + negatives)
- [x] Byte-exact HMAC on every signed engine fixture (both languages)
- [x] Chain: valid passes; broken/altered/duplicate rejected; checkpoint-covered
      gap accepted; forged checkpoint rejected (both)
- [x] Anchor: receipt/slice/checkpoint verify; tampered rejected (both)
- [x] Rust suite still green (25 + schema sync)

## Acceptance criteria

| # | Criterion | Where |
|---|-----------|-------|
| 1 | Python byte-exact on fixtures | `python/tests` |
| 2 | TypeScript byte-exact on fixtures | `typescript/test` |
| 3 | Negative tests (tamper/chain/sig) | both |
| 4 | No repo-relative corpus dep | `corpus` resolution (env → bundled) |
| 5 | CI green per language | `.github/workflows/ci.yml` |

## Status

- [x] Implemented
- [x] Local deterministic checks green
- [ ] MR pushed
- [ ] Merged
