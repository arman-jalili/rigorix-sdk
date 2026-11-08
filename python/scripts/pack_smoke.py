#!/usr/bin/env python3
"""Pack-time smoke test (SDK-C6-PACKAGING): run with the packed
``rigorix-verifier`` installed and ``RIGORIX_SDK_SCHEMAS`` unset. Proves the
wheel/sdist carries a REAL corpus.
"""

from __future__ import annotations

import json
from importlib.resources import files

from rigorix_verifier import fixture_text, schemas_root, verify_chain, verify_signature
from rigorix_verifier.binding import ARTIFACT_SHA256, Gate
from rigorix_verifier.client import Client, HTTPTransport

verify_signature(
    fixture_text("envelope/envelope-anchored-signed.json"), "fixture-hmac-key-2026"
)
verify_chain(json.loads(fixture_text("integrity/chain.json")))
print("packed python verifier smoke OK:", schemas_root())
# The wheel/sdist must carry the client subpackage too (SDL-2).
print("packed python client import OK:", Client.__name__, HTTPTransport.__name__)
# ... and the gate artifact (SDL-3).
artifact = files("rigorix_verifier").joinpath("_wasm/rigorix_gate_wasi.wasm")
assert artifact.is_file(), "the wheel/sdist is missing the WASI artifact"
print("packed python gate artifact OK:", Gate.__name__, ARTIFACT_SHA256[:12])
