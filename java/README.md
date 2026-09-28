# rigorix-verifier (Java)

Strategy A parity for the Rigorix signed audit trail: an **independent,
protocol-only** Java verifier + client. No `rigorix-engine` dependency.

- **HMAC-SHA256** over the canonical form (`signature` nulled) — byte-exact with
  the rigorix-oss engine and the other verifiers.
- **JSON Schema** conformance (draft 2020-12 via `com.networknt`).
- **ADR-016 chains**: per-producer sequence + `prev_hash` continuity, gaps
  accepted only when covered by a valid signed compaction checkpoint.
- **Ed25519 anchor artifacts** (BouncyCastle): ledger receipt, history slice,
  compaction checkpoint.
- **Client** (`dev.rigorix.sdk.client`): JSON-RPC 2.0 over a transport seam,
  binding every frozen `rigorix.*` catalog method (drift-tested).

## Contract corpus

`schemas/**` is **not** re-vendored: Maven copies the repo-root `schemas/` (the
single source of truth) into the jar under `rigorix/schemas/**` at build time, so
the published jar is self-contained. `Corpus.schema` / `Corpus.fixture` read it.

## Usage

```java
import dev.rigorix.sdk.Corpus;
import dev.rigorix.sdk.Envelope;

String anchored = Corpus.fixture("envelope/envelope-anchored-signed.json");
Envelope.verifySignature(anchored, "fixture-hmac-key-2026"); // byte-exact HMAC
Envelope.validateEnvelope(anchored);                         // schema conformance
```

## Test

```bash
cd java && mvn -B verify
```
