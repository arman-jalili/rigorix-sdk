<!-- history:document -->
# Contract sync — `rigorix.template.create` request shape (SDK 0.10.0)

**Date:** 2026-11-14
**Issue:** #138
**Status:** additive correction to `schemas/api/catalog.json`
(`$defs/planTemplate`) — no `apiVersion` change, no method added or removed
**Upstream:** `rigorix-oss` `214d53b3` (`rigorix-mcp` 1.14.3); the engine half is
rigorix-oss#1563

## Why

`$defs/planTemplate` set `additionalProperties: false` and declared five
properties: `name`, `description`, `steps`, `constraints`, `metadata`. The
engine's `PlanTemplate` (`mcp/src/template_tools/domain/value.rs`) accepts those
five **plus** `version` and `tags`, and requires `created_at`/`updated_at`, which
have no serde default. So there was no payload that satisfied both:

- follow the schema → `DeserializationFailed("missing field created_at")`;
- satisfy the engine → send fields the schema forbids.

Nothing caught it because every guard answered a different question: resolving
`$ref`s proves a schema is *well-formed*, and `catalog_drift_test` proves every
frozen method *has a binding*. Membership and compilation are not agreement with
the type the document describes. `$defs/templateGetResult` had required
`version`, `tags`, both timestamps all along — the response was written from the
type, the request from memory. **Two `$defs` describing one object and
disagreeing is the tell**: one of them had been re-read since the type last
changed, and the other had not.

## Decisions (code is truth, not implementer choice)

1. **The schema describes the request; the timestamps are not request fields.**
   `$defs/planTemplate` gains a `description` saying so, and does not declare
   `created_at`/`updated_at`. The stored shape stays `$defs/templateGetResult`
   (both required). A client that invents timestamps writes the host's clock into
   the engine's record — that is the workaround this fix exists to prevent.
2. **`version` and `tags` become optional request properties.** The engine
   declares both `#[serde(default)]`; the schema forbade them. Drift runs in both
   directions from the same omission.
3. **The step level is unchanged** — `$defs/stepDefinition` already declared all
   eight fields `StepDefinition` accepts (`name`, `tool`, `parameters`,
   `requires_approval`, `require_identity`, `description`, `timeout_secs`,
   `evaluate_score`). The issue's second refusal (`missing field
   requires_approval`) was a fixture problem, not a schema problem.

## The drift check this adds

`rust/rigorix-verifier`'s `template_create_covers_engine_accepted_fields` reads
`schemas/fixtures/template/engine-accepted-shape.json` — the engine's property
sets, captured from `PlanTemplate`/`StepDefinition` at the commit above (probe
and verbatim output in
[`PROVENANCE.md`](../schemas/fixtures/template/PROVENANCE.md)) — and fails when:

- a field the engine accepts is missing from the corresponding `$defs`
  (`additionalProperties: false` would make it unsendable);
- a field the server stamps is declared or required as a request field;
- `schemas/fixtures/template/create-request.json` (a payload built from
  `$defs/templateCreateParams`) does not validate against it.

Shown to bite: with `version`/`tags` removed the test fails naming `tags`; with
`created_at` declared as a request field it fails naming the stamping. A
`$ref`-resolving test passes in both states — which is why this one does not
resolve refs, it compares property sets.

## Residual (upstream, not worked around here)

At `214d53b3` a payload from this schema is still refused by the engine with
`missing field created_at`: the JSON create path demands what the TOML path
stamps (`engine_template_parser.rs:78-94`). Filed as rigorix-oss#1563. Measured:
the same payload **is** accepted once only the two timestamps are supplied
(`STAMPED: ACCEPTED` in the provenance file), so nothing else in it is refused.
When #1563 lands, the acceptance case in the issue ("a payload built from
`templateCreateParams` succeeds against `rigorix-server`") becomes executable
end-to-end; the fixture and its dated capture are already in place for that.

## Files

- `schemas/api/catalog.json` — `$defs/planTemplate`: `+version`, `+tags`,
  `description`
- `schemas/fixtures/template/{create-request,engine-accepted-shape}.json`,
  `PROVENANCE.md`, `README.md`
- `rust/rigorix-verifier/src/lib.rs` — `template_create_covers_engine_accepted_fields`
- `go/internal/corpus/corpus_gen.go` — regenerated (`go generate ./...`)