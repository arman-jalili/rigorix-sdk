"""rigorix-verifier (Python) — Strategy A parity for the signed audit trail.

Independent, protocol-only verification of Rigorix audit envelopes and the
frozen contract surface: HMAC-SHA256 over the canonical form, JSON Schema
conformance, ADR-016 per-producer chains, and Ed25519 anchor artifacts. No
engine dependency; the contract corpus comes from the bundled
``_schemas``/``RIGORIX_SDK_SCHEMAS`` copy (see :mod:`rigorix_verifier.corpus`).

```python
from rigorix_verifier import verify_chain, verify_signature

verify_signature(envelope_json, "fixture-hmac-key-2026")
verify_chain(envelopes)
```
"""

from .anchor import (
    verify_compaction_checkpoint,
    verify_history_slice,
    verify_ledger_receipt,
)
from .canonical import canonical_bytes, envelope_hash
from .chain import verify_chain, verify_chain_with_checkpoints
from . import client
from .corpus import fixture_text, schema_files, schema_text, schemas_root
from .envelope import validate_envelope, validate_schema, verify_signature
from .errors import (
    AnchorSignature,
    ChainBroken,
    SchemaViolation,
    SignatureMismatch,
    UnsignedNotDegraded,
    VerifyError,
)

__all__ = [
    "AnchorSignature",
    "ChainBroken",
    "SchemaViolation",
    "SignatureMismatch",
    "UnsignedNotDegraded",
    "VerifyError",
    "canonical_bytes",
    "client",
    "envelope_hash",
    "fixture_text",
    "schema_files",
    "schema_text",
    "schemas_root",
    "validate_envelope",
    "validate_schema",
    "verify_chain",
    "verify_chain_with_checkpoints",
    "verify_compaction_checkpoint",
    "verify_history_slice",
    "verify_ledger_receipt",
    "verify_signature",
]

__version__ = "0.9.0"
