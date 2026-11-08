#!/usr/bin/env python3
"""Pack-time smoke test (SDK-C6-PACKAGING): run with the packed
``rigorix-verifier`` installed and ``RIGORIX_SDK_SCHEMAS`` unset. Proves the
wheel/sdist carries a REAL corpus.
"""

from __future__ import annotations

import json

from rigorix_verifier import fixture_text, schemas_root, verify_chain, verify_signature
from rigorix_verifier.client import Client, HTTPTransport

verify_signature(
    fixture_text("envelope/envelope-anchored-signed.json"), "fixture-hmac-key-2026"
)
verify_chain(json.loads(fixture_text("integrity/chain.json")))
print("packed python verifier smoke OK:", schemas_root())
# The wheel/sdist must carry the client subpackage too (SDL-2).
print("packed python client import OK:", Client.__name__, HTTPTransport.__name__)
