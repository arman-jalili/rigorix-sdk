# `schemas/fixtures/events/` — SSE push event fixtures (ADR-0002 / SDK-C1)

One fixture per frozen ADR-0001 D8 push event. Each file is a logical
`ServerEvent` (`{ id, event, data }`) as reconstructed from an SSE frame; it
validates against [`schemas/api/events.json`](../../api/events.json) with the
envelope event-ref shape `$ref`'d from `envelope.json`.

| Fixture | SSE `event:` | `data.event_type` |
|---|---|---|
| `run-progress.json` | `run_progress` | `node_completed` |
| `approval-required.json` | `approval_required` | `approval_recorded` |
| `policy-changed.json` | `policy_changed` | `sequence_rule_matched` |

These are contract fixtures, not engine-produced run artifacts: the push stream
is not the signed artifact (the authoritative signed record remains the
envelope, retrievable via `rigorix.audit.read`). The verifier validates them
against `events.json`; it does not HMAC-verify them.

`cargo test -p rigorix-verifier events_fixtures_validate` is the gate.
