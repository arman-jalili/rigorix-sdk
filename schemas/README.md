# schemas/ — Rigorix canonical contracts

Single source of truth for every payload that crosses the Rigorix boundary. Both
implementation repos (rigorix-oss, rigorix-enterprise) and every language SDK read from
here. Drift is a CI failure.

## Status (2026-09-06)

- `envelope.json` — **draft v0** grounded in OSS `AuditEnvelope` (see delta notes); not
  yet authoritative — completion is contract-sync milestone 1.
- `policy.json` — pending (design in `../docs/contract-sync-2026-09-06.md`).
- `claims.json` — pending.
- `api/` — native `rigorix.*` method catalog: draft sketch only.
- `fixtures/` — real conference-demo envelopes + exported bundle + claim samples (to add).

## Field-name truth

Field names in these drafts are taken from OSS Rust structs (`serde` field names). If a
draft contradicts the code, **the code is truth** — file the delta, don't "fix" the draft
by guess. Additive fields use `skip_serializing_if`/serde-default semantics; absent =
absent in pre-feature envelopes (that's a feature, not a bug — see
`evidence_degraded`/GAP-M-12).
