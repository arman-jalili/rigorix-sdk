# Effect-commitment fixtures

Contract-first fixtures for [`api/effect-record.json`](../../api/effect-record.json)
(ADR-019).

The engine does not emit this artifact yet: OSS 1.11.0 ships the effect-commitment
bounded context, and the release rule says the SDK contract lands **before** the
servers claim it. The provider read-back bodies below are fixed inputs, and
`readback_digest` is `hex(SHA-256(UTF-8(bytes)))` — the same value
`engine/src/effect_commitment/infrastructure/provider_receipt.rs` computes. When
the engine exports the artifact, replace these with engine-produced fixtures.

## Accepted

| Fixture | What it proves |
|---|---|
| `committed-l1-l3.json` | **l1 durability + l3 settlement** is legal: the axes are orthogonal, not a ladder (#1182). |
| `not-committed-l2-l3.json` | Provider evidence can prove absence too; `not_committed` is terminal and carries evidence. |
| `dispatched-with-deadline.json` | Non-terminal record with a deadline and no evidence. |
| `ambiguous-unsettled.json` | Non-terminal, no evidence, yet the deployment claims `l3` — capability is not current settlement. |
| `resolved-ambiguous.json` | An ambiguous attempt settled by a resolver; the resolver rides inside `settlement`. |

## Rejected

| Fixture | Rejected by | Why |
|---|---|---|
| `rejected-terminal-without-evidence.json` | schema + structural | A terminal state must carry settlement (`EvidenceMissing`). |
| `rejected-nonterminal-with-settlement.json` | schema + structural | A non-terminal state must not carry an outcome or resolver (`Contended`). |
| `rejected-dispatched-without-deadline.json` | schema + structural | `dispatched` requires the store-clock deadline. |
| `rejected-verdict-mismatch.json` | schema + structural | The verdict must authorise the terminal state. |
| `rejected-readback-mismatch.json` | readback | Shape is valid; the digest does not match the carried bytes. |
| `rejected-readback-missing.json` | readback | Shape is valid; without the bytes the readback claim is refused. |
| `rejected-settlement-with-none-level.json` | structural | Evidence is present but `levels.settlement` says `none`. |

## Ceiling

A record is **not** bound to a signed audit envelope: it carries no signature and
the intent digest is not derivable from the envelope. Authenticity rests on the
signed envelope chain and the provider receipt. The readback level only proves
that the carried evidence matches the carried provider bytes.

## Pinned to the tests

Both sets are pinned in `rust/rigorix-verifier/src/lib.rs`:
`ACCEPTED_EFFECT_FIXTURES` and `REJECTED_EFFECT_FIXTURES` must equal the files in
this directory. Adding a `rejected-*.json` without a case, or a case without a
fixture, fails `effect_record_rejected_fixtures_are_pinned_and_rejected`. A
rejected fixture that no test names is inert coverage, not evidence.
