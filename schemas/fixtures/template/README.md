# Template fixtures

Contract-first fixtures for the five `rigorix.template.*` methods in
[`api/catalog.json`](../../api/catalog.json) (§`$defs/templateCreateParams`,
`templateGetResult`, …).

| Fixture | What it is |
|---|---|
| `create-request.json` | A full `rigorix.template.create` params payload built from `$defs/templateCreateParams` — the shape a client is told to send. |
| `engine-accepted-shape.json` | The fields the engine's `PlanTemplate`/`StepDefinition` actually accept, captured from the type at `214d53b3`; see [`PROVENANCE.md`](PROVENANCE.md). |

`create-request.json` is validated against `$defs/templateCreateParams` by
`template_create_covers_engine_accepted_fields` in
[`rust/rigorix-verifier`](../../../rust/rigorix-verifier), which also asserts that
every non-stamped field in `engine-accepted-shape.json` is *declarable* here.

## Why the two files disagree about timestamps

`$defs/planTemplate` describes the **request**; `created_at`/`updated_at` are
stamped by the server on create, on both paths (`rigorix-oss` `b606e33e`: the
create door stamps with the host clock and overwrites any value that arrives).
`$defs/templateGetResult` describes the **response**, and it has required both
timestamps since it was written from the type — which is why the two `$defs` used
to disagree about the same object, and why only the request was wrong (#138).

A payload built from this schema succeeded against `rigorix-server` at
`rigorix-oss` `b606e33e`, captured in `engine-accepted-shape.json` and
`create-request.json`: the response carried both timestamps, stamped with the
host's clock, identical across two reads two seconds apart. A client must not
invent them — the engine overwrites what it is given, so an invented clock never
reaches the record, and the round trip would only hide whose clock wrote it.