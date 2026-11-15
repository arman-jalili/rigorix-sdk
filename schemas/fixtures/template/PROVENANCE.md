# Where `engine-accepted-shape.json` came from

Measured, not inferred, at `rigorix-oss` commit
`214d53b31eec704cbf13b51189bb307fc125d60f` (2026-11-14T02:19:07+01:00), crate
`rigorix-mcp v1.14.3`, rustc 1.96.1.

The probe was a throwaway integration test inside that checkout (since removed):

```rust
use rigorix_mcp::template_tools::domain::PlanTemplate;

let req: serde_json::Value = serde_json::from_str(
    &std::fs::read_to_string("…/schemas/fixtures/template/create-request.json")?)?;
let plan = req["plan"].clone();

// (1) exactly as this repository documents it
println!("{:?}", PlanTemplate::from_json(plan.clone()));
// (2) with only the two timestamps supplied — what the TOML path already does,
//     and what the engine's half (rigorix-oss#1563) would do for JSON
plan["created_at"] = "2026-11-14T00:00:00Z";
plan["updated_at"] = "2026-11-14T00:00:00Z";
println!("{:?}", PlanTemplate::from_json(plan));
```

Output, verbatim:

```
AS_DOCUMENTED: Deserialization failed: Failed to deserialize PlanTemplate from JSON: missing field `created_at`
STAMPED: ACCEPTED
STAMPED_KEYS: ["constraints", "created_at", "description", "metadata", "name", "steps", "tags", "updated_at", "version"]
STAMPED_STEP_KEYS: ["description", "evaluate_score", "name", "parameters", "require_identity", "requires_approval", "timeout_secs", "tool"]
```

What that pair of lines means:

- **Everything except the stamping is accepted.** `version`, `tags`,
  `constraints`, `metadata` and every declared step field survive
  deserialisation; the only refusal left is `created_at`/`updated_at`, which the
  create path is supposed to stamp (`engine_template_parser.rs:78-94` does it for
  TOML; the JSON path does not — rigorix-oss#1563).
- So `engine-accepted-shape.json` lists the timestamps under `plan.server_stamped`
  rather than `plan.accepted`: they are fields of the *stored* type, not of the
  request.
- The serialised key sets are the accepted key sets because serde names the keys
  it writes and `PlanTemplate`/`StepDefinition` do not deny unknown fields.

`rust/rigorix-verifier`'s `template_create_covers_engine_accepted_fields` reads this
file, so the next drift — a field the engine gains and this catalog never hears
about — fails a test rather than shipping. Re-running the probe at a newer commit
and updating this file is how the record is advanced; the JSON is not edited from
memory.

## Second capture, 2026-11-15: the documented payload is accepted

The probe above measured the refusal. This capture measures the fix, against a server built from
`rigorix-oss` `1b425d51` (`b606e33e` is the create door; `385c81dd` is the read door):

```
POST /rpc rigorix.template.create   {"name":"sdk138-e2e","plan":<create-request.json's plan>}
  → {"name":"sdk138-e2e","path":".rigorix/templates/sdk138-e2e.toml","status":"created"}

POST /rpc rigorix.template.get      {"name":"sdk138-e2e"}
  → created_at 2026-11-15T18:05:37.823134Z   updated_at 2026-11-15T18:05:37.823134Z
  (two seconds later, identical)             ← the host's stamp, stable across reads
```

The payload carries no timestamps — it is `create-request.json` unchanged — and the response carries both. A run against the
same plan with `created_at`/`updated_at` set to `2000-01-01` also returned the host's clock, not the supplied value: the create
door overwrites rather than filling only, so a client-invented clock never reaches the record.
