"""Envelope HMAC + schema parity against the committed engine fixtures."""

from __future__ import annotations

import json

import pytest

import rigorix_verifier as rv
from rigorix_verifier import corpus

FIXTURE_KEY = "fixture-hmac-key-2026"


def _envelope_paths():
    root = corpus.schemas_root() / "fixtures" / "envelope"
    return sorted(root.glob("*.json"))


def test_signed_engine_fixtures_verify_byte_exact():
    signed = 0
    for path in _envelope_paths():
        text = path.read_text(encoding="utf-8")
        data = json.loads(text)
        if data.get("signature") is None:
            continue
        rv.verify_signature(text, FIXTURE_KEY)  # byte-exact canonical form
        rv.validate_envelope(text)  # schema conformance
        signed += 1
    assert signed >= 3, "expected >= 3 committed signed engine fixtures"


def test_tampering_is_detected():
    path = next(
        p for p in _envelope_paths() if json.loads(p.read_text()).get("signature")
    )
    data = json.loads(path.read_text())
    data["total_tokens"] = int(data.get("total_tokens", 0)) + 1
    with pytest.raises(rv.SignatureMismatch):
        rv.verify_signature(data, FIXTURE_KEY)


def test_unsigned_must_be_degraded():
    path = next(
        p for p in _envelope_paths() if json.loads(p.read_text()).get("signature") is None
    )
    data = json.loads(path.read_text())
    data["evidence_degraded"] = False
    with pytest.raises(rv.UnsignedNotDegraded):
        rv.verify_signature(data, FIXTURE_KEY)


def test_unsigned_degraded_is_accepted():
    path = next(
        p for p in _envelope_paths() if json.loads(p.read_text()).get("signature") is None
    )
    rv.verify_signature(path.read_text(), FIXTURE_KEY)


def test_schema_rejects_wrong_status_case():
    minimal = next(p for p in _envelope_paths() if "minimal" in p.name)
    data = json.loads(minimal.read_text())
    data["events"][0]["status"] = "success"  # engine emits "Success"
    with pytest.raises(rv.SchemaViolation):
        rv.validate_envelope(data)


def test_envelope_hash_is_stable():
    minimal = next(p for p in _envelope_paths() if "minimal" in p.name)
    first = rv.envelope_hash(minimal.read_text())
    second = rv.envelope_hash(json.loads(minimal.read_text()))
    assert first == second
    assert len(first) == 64
