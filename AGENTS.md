# rigorix-sdk — Agent Guidelines

Status: scaffold (docs + schemas drafts). No production code yet.

## Rules

1. **Code is truth.** Schema drafts must match rigorix-oss Rust structs (serde field
   names). If a draft contradicts the code, fix the draft from the code — never invent.
2. **Contract changes are decisions.** Any schema change goes through the drift CI story
   in rigorix-oss and gets a delta note here. No silent edits.
3. **Governed flows only.** SDK clients never expose a direct-execute path.
4. Docs live in `docs/`; contract-sync notes are append-only history.
