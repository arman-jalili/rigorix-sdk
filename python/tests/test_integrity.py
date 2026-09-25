"""ADR-016 chain + anchor parity against the committed integrity fixtures."""

from __future__ import annotations

import copy
import json

import pytest

import rigorix_verifier as rv
from rigorix_verifier import corpus

ANCHOR_PUBLIC_KEY = "ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c"


def _read(name: str):
    return json.loads(corpus.fixture_text(f"integrity/{name}"))


def test_valid_chain_verifies():
    rv.verify_chain(_read("chain.json"))


def test_broken_chain_is_rejected():
    with pytest.raises(rv.ChainBroken):
        rv.verify_chain(_read("broken-chain.json"))


def test_altered_predecessor_is_rejected():
    chain = _read("chain.json")
    chain[-1]["prev_hash"] = "0" * 64
    with pytest.raises(rv.ChainBroken):
        rv.verify_chain(chain)


def test_duplicate_sequence_is_rejected():
    chain = _read("chain.json")
    chain[-1]["sequence"] = chain[-2]["sequence"]
    with pytest.raises(rv.ChainBroken):
        rv.verify_chain(chain)


def test_checkpoint_covers_the_gap():
    broken = _read("broken-chain.json")
    checkpoint = _read("compaction-checkpoint.json")
    with pytest.raises(rv.ChainBroken):
        rv.verify_chain(broken)
    rv.verify_chain_with_checkpoints(broken, [checkpoint], ANCHOR_PUBLIC_KEY)


def test_forged_checkpoint_does_not_cover():
    broken = _read("broken-chain.json")
    forged = copy.deepcopy(_read("compaction-checkpoint.json"))
    forged["new_head"] = "0" * 64
    with pytest.raises(rv.AnchorSignature):
        rv.verify_chain_with_checkpoints(broken, [forged], ANCHOR_PUBLIC_KEY)


def test_history_slice_verifies():
    rv.verify_history_slice(_read("history-slice.json"), ANCHOR_PUBLIC_KEY)


def test_history_slice_tamper_is_rejected():
    forged = copy.deepcopy(_read("history-slice.json"))
    forged["actions"][0]["node"] = "forged_node"
    with pytest.raises(rv.AnchorSignature):
        rv.verify_history_slice(forged, ANCHOR_PUBLIC_KEY)


def test_ledger_receipt_verifies():
    rv.verify_ledger_receipt(_read("ledger-receipt.json"), ANCHOR_PUBLIC_KEY)


def test_compaction_checkpoint_verifies():
    rv.verify_compaction_checkpoint(_read("compaction-checkpoint.json"), ANCHOR_PUBLIC_KEY)
