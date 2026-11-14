"""The gate as a WASI artifact, embedded from Python via wasmtime.

The module decides; this wrapper allocates a request, calls `rigx_call`, reads
`[len: u32 LE][payload]` with host-side bounds checks, and returns the JSON.
The six WASI imports are answered with constants and counted. No decision logic
lives here.
"""

from __future__ import annotations

import json
import threading
from collections import OrderedDict
from dataclasses import dataclass
from typing import Any, Dict, Optional, Tuple

import wasmtime

from . import loader
from .errors import GateClosed, GateError, GateTrap, NotWASIArtifact

# ─── compiled-module cache ────────────────────────────────────────────────────
#
# Compiling the artifact dominates `Gate.open`: 253 ms warm / 355 ms cold for
# the 1.9 MB module on an 8-core aarch64 host, against ~0.04 ms for the
# decision it enables (#140). Compilation is a pure function of the bytes and
# the engine configuration, so it belongs to the process, not to the open.
#
# The cache holds (engine, module) because a `wasmtime.Module` is bound to the
# engine that compiled it; reusing the module means reusing the engine and
# creating a fresh `Store` per open. Default engine configuration is the only
# one this wrapper builds, and the key names it so a future non-default engine
# cannot silently inherit an incompatible module.
_ENGINE_CONFIGURATION = "default"

#: Bounded, because `open_unverified` accepts arbitrary bytes (tests, tooling):
#: an unbounded cache keyed by digest would be a leak with a friendly name.
_MAX_COMPILED = 4

_compiled: "OrderedDict[str, Tuple[wasmtime.Engine, wasmtime.Module]]" = OrderedDict()
_compiled_lock = threading.Lock()


def _compiled_module(wasm: bytes, digest: str) -> Tuple["wasmtime.Engine", "wasmtime.Module"]:
    """The compiled module for these bytes, compiling at most once per process.

    The import/export check runs here — once per compile, next to the compile it
    describes. It does not need to run per instantiation: `validate_module`
    reads the module's own import/export sections, which cannot change between
    stores, and the bytes behind a digest cannot either.
    """
    key = f"{_ENGINE_CONFIGURATION}:{digest}"
    with _compiled_lock:
        cached = _compiled.get(key)
        if cached is not None:
            _compiled.move_to_end(key)
            return cached

        engine = wasmtime.Engine()
        try:
            module = wasmtime.Module(engine, wasm)
        except wasmtime.WasmtimeError as exc:
            raise NotWASIArtifact(f"not a WebAssembly module: {exc}") from exc

        loader.validate_module(module)
        _compiled[key] = (engine, module)
        while len(_compiled) > _MAX_COMPILED:
            _compiled.popitem(last=False)
        return engine, module


def _reset_compiled_modules() -> None:
    """Drop the compiled-module cache. For tests; a decision does not call it."""
    with _compiled_lock:
        _compiled.clear()


@dataclass
class Counters:
    """The three answers that could silently become real."""

    clock_time_get_calls: int = 0
    random_get_calls: int = 0
    fd_write_bytes: int = 0


def _ft(params: int, results: int, i64_index: Optional[int] = None) -> "wasmtime.FuncType":
    """A fresh FuncType; ValType ownership is transferred, so never reuse one."""
    param_types = []
    for index in range(params):
        param_types.append(
            wasmtime.ValType.i64() if i64_index == index else wasmtime.ValType.i32()
        )
    return wasmtime.FuncType(param_types, [wasmtime.ValType.i32() for _ in range(results)])


def _memory(caller: "wasmtime.Caller") -> "wasmtime.Memory":
    memory = caller.get("memory")
    if memory is None:
        raise GateTrap("the module exported no memory")
    return memory


def _define_imports(linker: "wasmtime.Linker", counters: Counters) -> None:
    def environ_get(caller, environ, environ_buf):  # noqa: ARG001
        return 0

    def environ_sizes_get(caller, environc, environ_buf_size):
        memory = _memory(caller)
        memory.write(caller, b"\x00\x00\x00\x00", environc)
        memory.write(caller, b"\x00\x00\x00\x00", environ_buf_size)
        return 0

    def clock_time_get(caller, clock_id, precision, time):  # noqa: ARG001
        memory = _memory(caller)
        memory.write(caller, b"\x00" * 8, time)
        counters.clock_time_get_calls += 1
        return 0

    def random_get(caller, buf, buf_len):  # noqa: ARG001
        # The buffer is already zero; writing nothing is the deterministic answer.
        counters.random_get_calls += 1
        return 0

    def fd_write(caller, fd, iovs, iovs_len, nwritten):  # noqa: ARG001
        memory = _memory(caller)
        total = 0
        for index in range(iovs_len):
            raw = memory.read(caller, iovs + index * 8, iovs + index * 8 + 8)
            total += int.from_bytes(raw[4:8], "little")
        counters.fd_write_bytes += total
        memory.write(caller, b"\x00\x00\x00\x00", nwritten)
        return 0

    def proc_exit(caller, code):  # noqa: ARG001
        raise GateTrap(f"the module called proc_exit({code})")

    module = "wasi_snapshot_preview1"
    linker.define_func(module, "environ_get", _ft(2, 1), environ_get, access_caller=True)
    linker.define_func(
        module, "environ_sizes_get", _ft(2, 1), environ_sizes_get, access_caller=True
    )
    linker.define_func(
        module, "clock_time_get", _ft(3, 1, i64_index=1), clock_time_get, access_caller=True
    )
    linker.define_func(module, "random_get", _ft(2, 1), random_get, access_caller=True)
    linker.define_func(module, "fd_write", _ft(4, 1), fd_write, access_caller=True)
    linker.define_func(module, "proc_exit", _ft(1, 0), proc_exit, access_caller=True)


class Gate:
    """One opened session over the artifact; sealed after export."""

    def __init__(
        self,
        engine: "wasmtime.Engine",
        store: "wasmtime.Store",
        instance: "wasmtime.Instance",
        memory: "wasmtime.Memory",
        alloc,
        call,
        free,
        counters: Counters,
    ) -> None:
        self._engine = engine
        self._store = store
        self._instance = instance
        self._memory = memory
        self._alloc = alloc
        self._call_fn = call
        self._free = free
        self._counters = counters
        self._handle: Any = None
        self._closed = False

    @classmethod
    def open(
        cls,
        *,
        scenario: Any,
        fixtures: Any,
        clock: Any,
        seed: Any,
    ) -> "Gate":
        """Verify the vendored artifact against its recorded digest, then open.

        A digest mismatch is an `ArtifactDigestMismatch` naming both digests:
        the installed package is not the artifact that was built, and the gate
        refuses rather than deciding differently.

        What the caller pays: the first open in a process compiles the 1.9 MB
        module (~0.25 s measured); every later open pays one instantiation and
        one session (sub-millisecond), because the compiled module is cached per
        artifact digest and engine configuration. The digest and import/export
        checks run once per compile, not once per open — a module compiled from
        bytes verified in this process does not become different bytes later.
        """
        wasm = loader.artifact_bytes()
        digest = loader.verify_artifact(wasm)
        return cls._open_bytes(
            wasm, digest=digest, scenario=scenario, fixtures=fixtures, clock=clock, seed=seed
        )

    @classmethod
    def open_unverified(
        cls,
        *,
        artifact: bytes,
        scenario: Any,
        fixtures: Any,
        clock: Any,
        seed: Any,
    ) -> "Gate":
        """Open caller-supplied bytes (tests, tooling) without the digest check.

        The import/export shape is still enforced. The name says the rest: these
        bytes have not been checked against the recorded artifact.
        """
        return cls._open_bytes(artifact, scenario=scenario, fixtures=fixtures, clock=clock, seed=seed)

    @classmethod
    def _open_bytes(
        cls,
        wasm: bytes,
        *,
        digest: Optional[str] = None,
        scenario: Any,
        fixtures: Any,
        clock: Any,
        seed: Any,
    ) -> "Gate":
        engine, module = _compiled_module(
            wasm, digest if digest is not None else loader.artifact_digest(wasm)
        )
        store = wasmtime.Store(engine)
        counters = Counters()
        linker = wasmtime.Linker(engine)
        _define_imports(linker, counters)
        try:
            instance = linker.instantiate(store, module)
        except wasmtime.WasmtimeError as exc:
            raise NotWASIArtifact(f"not the WASI artifact: {exc}") from exc

        exports = instance.exports(store)
        missing = [name for name in loader.EXPORTS if name not in exports]
        if missing:
            raise NotWASIArtifact(f"not the WASI artifact: missing export {missing[0]}")

        gate = cls(
            engine,
            store,
            instance,
            exports["memory"],
            exports["rigx_alloc"],
            exports["rigx_call"],
            exports["rigx_free"],
            counters,
        )
        opened = gate._raise_refusal(
            gate._exchange(
                _encode(
                    {
                        "op": "open_session",
                        "scenario": scenario,
                        "fixtures": fixtures,
                        "clock": clock,
                        "seed": seed,
                    }
                )
            )
        )
        handle = opened.get("handle")
        if handle is None:
            raise GateError("request_invalid", "open_session returned no handle")
        gate._handle = handle
        return gate

    @property
    def counters(self) -> Counters:
        """The clock/random/stdout counters; all must stay zero across a decision."""
        return self._counters

    def call_raw(self, request: str) -> Dict[str, Any]:
        """Send raw request bytes (used by the refusal tests)."""
        return self._raise_refusal(self._exchange(request.encode("utf-8")))

    def attempt(self, action: Dict[str, Any]) -> Dict[str, Any]:
        """Drive the session's one attempt; a refusal is returned as a `kind` object."""
        if self._closed:
            raise GateClosed("gate session is sealed")
        request = _encode(
            {
                "op": "attempt_run",
                "handle": {"handle": self._handle},
                "action": action,
            }
        )
        return self._raise_refusal(self._exchange(request))

    def export_artifact_set(self) -> Dict[str, Any]:
        """Seal the session and return the artifact set."""
        if self._closed:
            raise GateClosed("gate session is sealed")
        request = _encode(
            {"op": "export_artifact_set", "handle": {"handle": self._handle}}
        )
        exported = self._raise_refusal(self._exchange(request))
        self._closed = True
        return exported

    def contract_version(self) -> Dict[str, Any]:
        """Ask the artifact for its contract/engine/format numbers."""
        return self._raise_refusal(self._exchange(_encode({"op": "contract_version"})))

    def close(self) -> None:
        """Seal the wrapper's handle; the artifact instance is released with it."""
        self._closed = True

    def __enter__(self) -> "Gate":
        return self

    def __exit__(self, *exc_info: Any) -> None:
        self.close()

    def _raise_refusal(self, response: Dict[str, Any]) -> Dict[str, Any]:
        if "kind" in response:
            raise GateError(
                str(response["kind"]),
                str(response.get("message", "")),
            )
        return response

    def _exchange(self, request: bytes) -> Dict[str, Any]:
        """One alloc/write/call/read/free cycle with the host-side bounds rule."""
        try:
            ptr = self._alloc(self._store, len(request))
            if not isinstance(ptr, int) or ptr == 0:
                raise GateError("protocol", "rigx_alloc refused the request buffer")
            try:
                self._memory.write(self._store, request, ptr)
                response = self._call_fn(self._store, ptr, len(request))
            finally:
                self._free(self._store, ptr, len(request))

            if not isinstance(response, int) or response == 0:
                raise GateError("protocol", "rigx_call produced no response")

            size = self._memory.data_len(self._store)
            if response + 4 > size:
                raise GateError(
                    "protocol",
                    f"the response pointer {response} leaves no length prefix in {size} bytes",
                )
            length = int.from_bytes(
                bytes(self._memory.read(self._store, response, response + 4)), "little"
            )
            if length > size - response - 4:
                raise GateError(
                    "protocol",
                    f"the response claims {length} bytes at {response}, "
                    f"but only {size - response - 4} remain",
                )
            raw = bytes(
                self._memory.read(self._store, response + 4, response + 4 + length)
            )
            self._free(self._store, response, length + 4)
        except (GateError, GateClosed, GateTrap, NotWASIArtifact):
            raise
        except wasmtime.WasmtimeError as exc:
            raise GateTrap(f"the WASI artifact trapped: {exc}") from exc

        try:
            value = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise GateError("protocol", f"the response is not JSON: {exc}") from exc
        if not isinstance(value, dict):
            raise GateError("protocol", "the response is not a JSON object")
        return value


def _encode(request: Dict[str, Any]) -> bytes:
    return json.dumps(request, separators=(",", ":")).encode("utf-8")
