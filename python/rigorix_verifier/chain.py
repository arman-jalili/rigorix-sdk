"""ADR-016 local per-producer chain verification."""

from __future__ import annotations

from .anchor import verify_compaction_checkpoint
from .canonical import envelope_hash
from .errors import ChainBroken

_CHAIN_FIELDS = ("producer_id", "sequence")


def verify_chain(envelopes: list[dict]) -> None:
    """Verify the strict local chain (no gap is accepted)."""
    verify_chain_with_checkpoints(envelopes, [], "")


def verify_chain_with_checkpoints(
    envelopes: list[dict],
    checkpoints: list[dict],
    anchor_public_key_hex: str,
) -> None:
    """Verify the chain, accepting a gap iff a valid signed checkpoint covers it.

    A covered gap requires ``sequence_from == prev+1``,
    ``sequence_to == next-1``, ``prior_head == envelope_hash(prev)`` and
    ``new_head == prev_hash(next)``.
    """
    for checkpoint in checkpoints:
        verify_compaction_checkpoint(checkpoint, anchor_public_key_hex)

    producers: dict[str, list[dict]] = {}
    for envelope in envelopes:
        producer = envelope.get("producer_id")
        sequence = envelope.get("sequence")
        if producer is not None and sequence is not None:
            producers.setdefault(producer, []).append(envelope)

    for producer in sorted(producers):
        chain = sorted(producers[producer], key=lambda e: e["sequence"])
        base = chain[0]["sequence"]
        if base != 0:
            raise ChainBroken(
                f"producer '{producer}': chain starts at sequence {base}, "
                "not genesis 0 — the earliest envelope(s) were deleted"
            )
        if chain[0].get("prev_hash") is not None:
            raise ChainBroken(
                f"producer '{producer}': genesis envelope carries a prev_hash"
            )
        for prev, nxt in zip(chain, chain[1:]):
            prev_sequence = prev["sequence"]
            next_sequence = nxt["sequence"]
            if next_sequence <= prev_sequence:
                raise ChainBroken(
                    f"producer '{producer}': sequence not strictly increasing "
                    f"({prev_sequence} -> {next_sequence})"
                )
            prev_hash = envelope_hash(prev)
            if next_sequence == prev_sequence + 1:
                actual = nxt.get("prev_hash")
                if actual != prev_hash:
                    raise ChainBroken(
                        f"producer '{producer}': prev_hash mismatch at sequence "
                        f"{next_sequence}"
                    )
                continue
            link = nxt.get("prev_hash")
            if link is None:
                raise ChainBroken(
                    f"producer '{producer}': missing prev_hash after gap at "
                    f"sequence {next_sequence}"
                )
            covered = any(
                checkpoint.get("sequence_from") == prev_sequence + 1
                and checkpoint.get("sequence_to") == next_sequence - 1
                and checkpoint.get("prior_head") == prev_hash
                and checkpoint.get("new_head") == link
                for checkpoint in checkpoints
            )
            if not covered:
                raise ChainBroken(
                    f"producer '{producer}': uncovered gap sequences "
                    f"{prev_sequence + 1}..={next_sequence - 1}"
                )


__all__ = ["verify_chain", "verify_chain_with_checkpoints"]
