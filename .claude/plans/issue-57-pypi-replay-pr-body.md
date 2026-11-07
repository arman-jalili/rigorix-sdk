## Summary

Refs #57 (Maven remains blocked on the Central credential; this is the replay-gap fix).

Re-running the `v0.9.0` publish exposed a non-idempotent step: PyPI failed with
`400 File already exists` because 0.9.0 was already live. A version already on the
index is done, not broken — the same rule the npm jobs already apply.

## Change

Before `pypa/gh-action-pypi-publish`, query
`https://pypi.org/pypi/rigorix-verifier/<version>/json`:

- `200` → set `already=true`, skip the publish step, and log that the version is present.
- anything else → publish as before.

The version comes from `python/pyproject.toml`, which the job already asserts
matches the tag.

## Verification

```
YAML parse                                             ✅
PyPI rigorix-verifier 0.9.0  -> 200 (would skip)       ✅
PyPI rigorix-verifier 9.9.9  -> 404 (would publish)    ✅
```

No code or artifact change; the Node/Java/Python/Go/Rust suites are untouched.

## Context

The refreshed Central username/token were applied to the Actions secrets and the
`v0.9.0` run was replayed. npm replayed cleanly; PyPI hit the duplicate-file
error above; Maven still returns `401 Invalid request` from the Central Portal
(signing succeeds), so the credential/namespace authorization is still the
blocker. #57 stays open until `maven-metadata.xml` reports `release: 0.9.0`.
