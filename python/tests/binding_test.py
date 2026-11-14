"""SDL-3: the gate in-process over the WASI artifact, through wasmtime."""

from __future__ import annotations

import base64
import builtins
import hashlib
import json
import os
import platform
import re
import socket
import subprocess
from pathlib import Path

import pytest

from rigorix_verifier.binding import (
    ARTIFACT_SHA256,
    ARTIFACT_SIZE,
    IMPORTS,
    ArtifactDigestMismatch,
    Gate,
    GateClosed,
    GateError,
    NotWASIArtifact,
    artifact_bytes,
    runtime_version,
)
from rigorix_verifier.binding import loader

VECTORS = Path(__file__).resolve().parent / "binding" / "vectors"

pytestmark = pytest.mark.skipif(
    platform.system() == "Darwin" and os.environ.get("RIGORIX_WASMTIME_JIT") != "1",
    reason=(
        "wasmtime's JIT is blocked by this macOS sandbox (even a trivial "
        "i32.const is SIGKILLed); Linux CI runs the binding tests"
    ),
)


def _vector(name: str) -> dict:
    return json.loads((VECTORS / f"{name}.json").read_text(encoding="utf-8"))


def _open(vector: dict, artifact: bytes | None = None) -> Gate:
    session = {
        "scenario": vector["scenario"],
        "fixtures": vector["fixtures"],
        "clock": vector["clock"],
        "seed": vector["seed"],
    }
    if artifact is None:
        return Gate.open(**session)
    return Gate.open_unverified(artifact=artifact, **session)


def _matches(outcome: dict, expected: dict) -> bool:
    canonical = base64.b64encode(bytes.fromhex(expected["hex"])).decode("ascii")
    return (
        outcome["decision_digest"] == expected["sha256"]
        and outcome["decision_canonical"] == canonical
    )


def test_open_compiles_the_artifact_once(monkeypatch):
    """#140: compilation and the import/export check belong to the process.

    `wasmtime.Module` costs ~0.25 s for this artifact, while a decision costs
    ~0.04 ms. Compiling per open made every decision pay for it; the module is
    now cached per artifact digest, so two opens compile once and validate the
    shape once, and only the store/session is per open.
    """
    import wasmtime

    from rigorix_verifier.binding import gate as gate_module

    vector = _vector("vec-fixture-0001")
    gate_module._reset_compiled_modules()

    compiles = []
    validations = []
    real_module = wasmtime.Module
    real_validate = gate_module.loader.validate_module

    def counting_module(engine, wasm, *args, **kwargs):
        compiles.append(len(wasm))
        return real_module(engine, wasm, *args, **kwargs)

    def counting_validate(module):
        validations.append(1)
        return real_validate(module)

    monkeypatch.setattr(gate_module.wasmtime, "Module", counting_module)
    monkeypatch.setattr(gate_module.loader, "validate_module", counting_validate)

    first = _open(vector)
    second = _open(vector)
    try:
        assert compiles == [ARTIFACT_SIZE], (
            f"compiled {len(compiles)} time(s) for two opens: the cache missed"
        )
        assert len(validations) == 1, (
            f"validated the import/export shape {len(validations)} time(s) for two opens"
        )
        # The cache shares the module, never the session.
        assert first is not second
        assert first.attempt(vector["scenario"]["action"]) is not None
        assert second.attempt(vector["scenario"]["action"]) is not None
    finally:
        first.close()
        second.close()

    # The unverified path is keyed the same way: same bytes, same compiled
    # module — the digest is what the key is made of, so nothing unverified can
    # inherit an entry compiled from other bytes.
    third = _open(vector, artifact=artifact_bytes())
    try:
        assert compiles == [ARTIFACT_SIZE], "the unverified path recompiled identical bytes"
    finally:
        third.close()


def test_all_five_vectors():
    paths = sorted(VECTORS.glob("*.json"))
    assert len(paths) == 5, "the artifact claims five vectors"

    for path in paths:
        vector = json.loads(path.read_text(encoding="utf-8"))
        gate = _open(vector)
        try:
            outcome = gate.attempt(vector["scenario"]["action"])
            matched = _matches(outcome, vector["expected_decision"])
            if vector["seeded_divergence"]:
                assert not matched, f"{vector['id']} must diverge from the recorded decision"
            else:
                assert matched, (
                    f"{vector['id']}: digest {outcome['decision_digest']} != "
                    f"{vector['expected_decision']['sha256']}"
                )
            gate.export_artifact_set()
            # The #1477 invariant is the clock: the allow path must not read it.
            # `random_get` may be called once by `std` while sealing (an inert
            # prologue read); it is counted, and the decision digests above are
            # the proof that no decision consumed it.
            assert gate.counters.clock_time_get_calls == 0
            assert gate.counters.fd_write_bytes == 0
        finally:
            gate.close()


def test_capacity_operands():
    vector = _vector("vec-0002")
    gate = _open(vector)
    try:
        step = gate.attempt(vector["scenario"]["action"])["steps"][0]
    finally:
        gate.close()
    assert step["kind"] == "capacity_exceeded"
    assert step["detail"]["kind"] == "capacity"
    assert step["detail"]["overage"] == 7420
    assert step["detail"]["claimed"] == 1427420


def test_duplicate_effect_operands():
    vector = _vector("vec-0003")
    gate = _open(vector)
    try:
        step = gate.attempt(vector["scenario"]["action"])["steps"][0]
    finally:
        gate.close()
    assert step["kind"] == "duplicate_effect"
    assert step["detail"]["kind"] == "duplicate_effect"
    assert step["detail"]["record_id"] == "QR-2041"


def test_no_io_at_decision_time(monkeypatch):
    vector = _vector("vec-0001")
    gate = _open(vector)
    try:
        def refuse(*args, **kwargs):  # noqa: ARG001
            raise AssertionError("the decision touched the host")

        monkeypatch.setattr(builtins, "open", refuse)
        monkeypatch.setattr(socket, "socket", refuse)
        monkeypatch.setattr(subprocess, "Popen", refuse)
        outcome = gate.attempt(vector["scenario"]["action"])
        assert outcome["status"] == "allowed"
    finally:
        gate.close()


def test_sealed_session_refuses_a_stale_handle():
    vector = _vector("vec-0001")
    gate = _open(vector)
    try:
        gate.attempt(vector["scenario"]["action"])
        gate.export_artifact_set()
        with pytest.raises(GateClosed):
            gate.attempt(vector["scenario"]["action"])
        with pytest.raises(GateClosed):
            gate.export_artifact_set()
    finally:
        gate.close()


def test_truncated_request_is_request_invalid_and_instance_survives():
    vector = _vector("vec-0001")
    gate = _open(vector)
    try:
        with pytest.raises(GateError) as caught:
            gate.call_raw('{"op":"attempt_run","handle":{"hand')
        assert caught.value.kind == "request_invalid"
        assert gate.contract_version()["contract"]
    finally:
        gate.close()


def test_unknown_op_is_request_invalid():
    vector = _vector("vec-0001")
    gate = _open(vector)
    try:
        with pytest.raises(GateError) as caught:
            gate.call_raw('{"op":"nope"}')
        assert caught.value.kind == "request_invalid"
    finally:
        gate.close()


def _module_with_import(module: str = "__wbindgen_placeholder__", name: str = "__wbindgen_throw") -> bytes:
    mod = module.encode("utf-8")
    field = name.encode("utf-8")
    type_section = b"\x01\x04\x01\x60\x00\x00"
    payload = b"\x01" + bytes([len(mod)]) + mod + bytes([len(field)]) + field + b"\x00\x00"
    return b"\x00asm\x01\x00\x00\x00" + type_section + b"\x02" + bytes([len(payload)]) + payload


def test_browser_module_is_refused_by_name():
    vector = _vector("vec-0001")
    with pytest.raises(NotWASIArtifact, match="__wbindgen_placeholder__"):
        _open(vector, artifact=_module_with_import())


def test_artifact_digest_and_size_are_recorded():
    raw = artifact_bytes()
    assert len(raw) == ARTIFACT_SIZE
    assert hashlib.sha256(raw).hexdigest() == ARTIFACT_SHA256
    loader.verify_artifact(raw)  # the load-time check accepts the recorded bytes

    with pytest.raises(ArtifactDigestMismatch):
        loader.verify_artifact(raw[:-1])


def test_the_runtime_pin_is_the_runtime_that_runs():
    """SDL-5: the number in the report is the number in the manifest."""
    pyproject = (Path(__file__).resolve().parent.parent / "pyproject.toml").read_text(
        encoding="utf-8"
    )
    pinned = re.search(r'"wasmtime==([0-9]+\.[0-9]+\.[0-9]+)"', pyproject)
    assert pinned, "pyproject.toml must carry an exact wasmtime pin"
    assert runtime_version() == pinned.group(1)


def test_a_modified_artifact_is_refused_at_load(monkeypatch):
    edited = bytearray(artifact_bytes())
    edited[len(edited) // 2] ^= 0xFF

    def tampered() -> bytes:
        return bytes(edited)

    monkeypatch.setattr(loader, "artifact_bytes", tampered)
    vector = _vector("vec-0001")
    with pytest.raises(ArtifactDigestMismatch) as refusal:
        _open(vector)

    expected = hashlib.sha256(bytes(edited)).hexdigest()
    assert refusal.value.expected == ARTIFACT_SHA256
    assert refusal.value.actual == expected
    assert ARTIFACT_SHA256 in str(refusal.value)
    assert expected in str(refusal.value)
    assert isinstance(refusal.value, NotWASIArtifact)


def test_the_honest_artifact_opens_through_the_verified_entry_point():
    vector = _vector("vec-0001")
    gate = _open(vector)
    try:
        assert gate.contract_version()["gate_evaluation"] is True
    finally:
        gate.close()


def test_the_record_is_six_imports():
    assert len(IMPORTS) == 6
    vector = _vector("vec-0001")
    gate = _open(vector)
    try:
        version = gate.contract_version()
        assert version["gate_evaluation"] is True
        assert version["contract"] == "1.14.3"
    finally:
        gate.close()


def test_a_wrong_digest_is_named():
    vector = _vector("vec-0001")
    gate = _open(vector)
    try:
        outcome = gate.attempt(vector["scenario"]["action"])
    finally:
        gate.close()
    edited = dict(vector["expected_decision"])
    edited["sha256"] = "sha256:" + "0" * 64
    matched = _matches(outcome, edited)
    assert not matched
    with pytest.raises(AssertionError, match="vec-0001"):
        assert matched, (
            f"{vector['id']}: digest {outcome['decision_digest']} != "
            f"{edited['sha256']}"
        )


def test_no_policy_in_python():
    forbidden = (
        "payment_execute",
        "capacity_exceeded",
        "duplicate_effect",
        "overage",
        "eligibility.check",
        "budget.check",
    )
    for path in Path(loader.__file__).resolve().parent.glob("*.py"):
        text = path.read_text(encoding="utf-8")
        for term in forbidden:
            assert term not in text, f"{path.name} contains policy term {term!r}"
