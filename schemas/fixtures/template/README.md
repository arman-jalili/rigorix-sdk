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
stamped by the server on create (`engine_template_parser.rs:78-94` for the TOML
path; the JSON path is the subject of rigorix-oss#1563). `$defs/templateGetResult`
describes the **response**, and it has required both timestamps since it was
written from the type — which is why the two `$defs` used to disagree about the
same object, and why only the request was wrong (#138).

Until the engine stamps on create, a payload from this schema is refused with
`missing field created_at` — a defect in the engine, named there rather than
worked around here: a client that invents timestamps writes the host's clock into
the engine's record.