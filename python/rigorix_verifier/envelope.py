"""Envelope HMAC verification + JSON Schema conformance."""

from __future__ import annotations

import hashlib
import hmac
import json
from functools import lru_cache
from typing import Any

from .canonical import canonical_bytes
from .corpus import schema_files, schema_text
from .errors import SchemaViolation, SignatureMismatch, UnsignedNotDegraded, VerifyError


def verify_signature(envelope: dict | str, key: str) -> None:
    """Verify an envelope's HMAC-SHA256 over its canonical bytes.

    A ``signature: null`` envelope is accepted only when
    ``evidence_degraded == true`` (GAP-M-12); otherwise it is a failure.
    """
    if isinstance(envelope, str):
        envelope = json.loads(envelope)
    signature = envelope.get("signature")
    if signature is None:
        if envelope.get("evidence_degraded") is True:
            return
        raise UnsignedNotDegraded(
            "unsigned envelope without evidence_degraded=true (GAP-M-12 violation)"
        )
    expected = hmac.new(
        key.encode("utf-8"), canonical_bytes(envelope), hashlib.sha256
    ).hexdigest()
    if not hmac.compare_digest(expected, signature):
        raise SignatureMismatch(
            f"signature mismatch: expected {expected}, got {signature}"
        )


@lru_cache(maxsize=1)
def _registry():
    """A `referencing` registry of every embedded schema, keyed by ``$id``."""
    from referencing import Registry, Resource

    resources = []
    for rel in schema_files():
        try:
            doc = json.loads(schema_text(rel))
        except (ValueError, OSError):
            continue
        if isinstance(doc, dict) and isinstance(doc.get("$id"), str):
            resources.append((doc["$id"], Resource.from_contents(doc)))
    return Registry().with_resources(resources)


def validate_schema(schema_rel: str, instance: dict | str) -> None:
    """Validate ``instance`` against the named contract schema."""
    from jsonschema import Draft202012Validator

    if isinstance(instance, str):
        instance = json.loads(instance)
    schema = json.loads(schema_text(schema_rel))
    validator = Draft202012Validator(schema, registry=_registry())
    errors = sorted(validator.iter_errors(instance), key=lambda e: list(e.path))
    if errors:
        raise SchemaViolation("; ".join(err.message for err in errors))


def validate_envelope(instance: dict | str) -> None:
    """Validate an envelope against ``envelope.json``."""
    validate_schema("envelope.json", instance)


__all__ = [
    "VerifyError",
    "verify_signature",
    "validate_schema",
    "validate_envelope",
]
