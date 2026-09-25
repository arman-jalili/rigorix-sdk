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


def test_anchored_fixture_binds_anchor_head_at_engine_position():
    """ADR-016 Phase C regression: the anchored engine fixture's HMAC reproduces
    only when `anchor_head` is placed after `history_policy` (before
    `approval_events`). Before the field was declared it was dropped -> mismatch.
    """
    path = (
        corpus.schemas_root()
        / "fixtures"
        / "envelope"
        / "envelope-anchored-signed.json"
    )
    text = path.read_text(encoding="utf-8")
    data = json.loads(text)
    assert data["history_integrity"] == "anchored"
    assert data["anchor_head"] == "3f2a9c1e7b4d5f6081a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708"
    assert data["approval_events"], "fixture must carry approval_events (position proof)"

    # Byte-exact parity — the regression: the field is NOT dropped.
    rv.verify_signature(text, FIXTURE_KEY)
    rv.validate_envelope(text)

    # The field is part of the signed bytes; tampering is detected.
    tampered = json.loads(text)
    tampered["anchor_head"] = "0" * 64
    with pytest.raises(rv.SignatureMismatch):
        rv.verify_signature(tampered, FIXTURE_KEY)

    # A local_unanchored fixture (ADR-016 Phase A chain) carries no anchor_head
    # and still verifies — skip-if-none keeps its bytes unchanged.
    chain = json.loads(
        (corpus.schemas_root() / "fixtures" / "integrity" / "chain.json").read_text(
            encoding="utf-8"
        )
    )
    assert chain[0]["history_integrity"] == "local_unanchored"
    assert chain[0].get("anchor_head") is None
    rv.verify_signature(json.dumps(chain[0]), FIXTURE_KEY)

    # Legacy fixtures (no integrity tag) also carry no anchor_head.
    legacy = next(p for p in _envelope_paths() if "minimal" in p.name)
    assert json.loads(legacy.read_text()).get("anchor_head") is None
    rv.verify_signature(legacy.read_text(), FIXTURE_KEY)
