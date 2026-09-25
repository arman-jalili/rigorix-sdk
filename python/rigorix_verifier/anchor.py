"""ADR-016 anchor-signed artifacts — Ed25519 verification (spec-only).

Canonical signing form (documented per schema): Ed25519 over the compact JSON
of the artifact with ``sig`` set to ``null``. The envelope's
``prev_hash``/``envelope_hash`` use the HMAC canonical bytes instead; only the
anchor artifacts use Ed25519.
"""

from __future__ import annotations

import json
from typing import Any

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

from .errors import AnchorSignature

_LEDGER_RECEIPT = ("ledger_id", "envelope_hash", "sequence", "recorded_at", "sig")
_HISTORY_SLICE = ("scope", "since", "actions", "head_hash", "sig")
_COMPACTION_CHECKPOINT = (
    "sequence_from",
    "sequence_to",
    "reason",
    "prior_head",
    "new_head",
    "sig",
)
_HISTORY_ACTION = ("node", "principal", "at", "effect_key")


def _signing_bytes(artifact: dict, order: tuple[str, ...]) -> bytes:
    out: dict[str, Any] = {}
    for field in order:
        if field not in artifact:
            continue
        value = artifact[field]
        if field == "sig":
            out[field] = None
        elif field == "actions" and isinstance(value, list):
            out[field] = [
                {
                    key: action[key]
                    for key in _HISTORY_ACTION
                    if key in action and not (key == "effect_key" and action[key] is None)
                }
                for action in value
            ]
        else:
            out[field] = value
    return json.dumps(out, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _verify(artifact: dict, order: tuple[str, ...], public_key_hex: str) -> None:
    signature = artifact.get("sig")
    if not signature:
        raise AnchorSignature("artifact has no `sig`")
    try:
        public_key = Ed25519PublicKey.from_public_bytes(bytes.fromhex(public_key_hex))
    except (ValueError, TypeError) as exc:
        raise AnchorSignature(f"invalid public key: {exc}") from exc
    try:
        public_key.verify(bytes.fromhex(signature), _signing_bytes(artifact, order))
    except (InvalidSignature, ValueError) as exc:
        raise AnchorSignature("invalid Ed25519 anchor signature") from exc


def verify_ledger_receipt(receipt: dict, public_key_hex: str) -> None:
    _verify(receipt, _LEDGER_RECEIPT, public_key_hex)


def verify_history_slice(history_slice: dict, public_key_hex: str) -> None:
    _verify(history_slice, _HISTORY_SLICE, public_key_hex)


def verify_compaction_checkpoint(checkpoint: dict, public_key_hex: str) -> None:
    _verify(checkpoint, _COMPACTION_CHECKPOINT, public_key_hex)


__all__ = [
    "verify_ledger_receipt",
    "verify_history_slice",
    "verify_compaction_checkpoint",
]
