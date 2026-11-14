"""Protocol client against the frozen catalog (SDL-2)."""

from __future__ import annotations

import http.server
import json
import os
import re
import socket
import threading
import time
from pathlib import Path

import pytest

from rigorix_verifier import corpus
from rigorix_verifier.client import (
    BatchCall,
    Client,
    HTTPTransport,
    IncompatibleVersion,
    MockTransport,
    ProtocolError,
    RpcError,
    TransportError,
)
from rigorix_verifier.client import catalog


def _result_body(result=None, request_id=1):
    return json.dumps(
        {"jsonrpc": "2.0", "id": request_id, "result": {} if result is None else result}
    )


def _version_body(request_id=1, api_version="1.0.0"):
    return json.dumps(
        {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {
                "name": "rigorix",
                "engine_version": "1.7.0",
                "api_version": api_version,
                "schemas": [],
                "capabilities": [],
            },
        }
    )


class RaisingTransport:
    def __init__(self, error):
        self.error = error

    def post(self, body):  # noqa: ARG002 (transport signature)
        raise self.error


def test_all_typed_methods_send_the_frozen_names():
    cases = [
        ("rigorix.plan", lambda c: c.plan({"template_name": "t"})),
        ("rigorix.validatePlan", lambda c: c.validate_plan({"plan": {}})),
        ("rigorix.run", lambda c: c.run({"template_name": "t"})),
        ("rigorix.execute", lambda c: c.execute({"template_name": "t"})),
        ("rigorix.approve", lambda c: c.approve({"execution_id": "e", "step_names": ["s"]})),
        ("rigorix.checkEnforcement", lambda c: c.check_enforcement()),
        ("rigorix.audit.read", lambda c: c.audit_read({"execution_id": "e"})),
        ("rigorix.audit.list", lambda c: c.audit_list({})),
        ("rigorix.audit.summary", lambda c: c.audit_summary({})),
        ("rigorix.template.list", lambda c: c.template_list({})),
        ("rigorix.template.get", lambda c: c.template_get({"name": "t"})),
        ("rigorix.template.create", lambda c: c.template_create({"name": "t", "plan": {}})),
        ("rigorix.template.validate", lambda c: c.template_validate({"plan": {}})),
        ("rigorix.auth.login", lambda c: c.auth_login({})),
        ("rigorix.auth.status", lambda c: c.auth_status()),
        ("rigorix.auth.logout", lambda c: c.auth_logout()),
        ("rigorix.usageGuide", lambda c: c.usage_guide()),
        ("rigorix.system.version", lambda c: c.version()),
    ]
    assert len(cases) == 18

    for method, invoke in cases:
        body = _version_body() if method == "rigorix.system.version" else _result_body()
        transport = MockTransport([body])
        invoke(Client(transport))
        sent = json.loads(transport.requests[0])
        assert sent["jsonrpc"] == "2.0"
        assert sent["method"] == method


def test_version_accepts_v1():
    version = Client(MockTransport([_version_body()])).version()
    assert version["api_version"] == "1.0.0"


def test_version_refuses_other_major():
    with pytest.raises(IncompatibleVersion) as caught:
        Client(MockTransport([_version_body(api_version="v2")])).version()
    assert caught.value.server == "v2"
    assert caught.value.client_major == 1
    assert "v2" in str(caught.value)


def test_mismatched_id_is_refused():
    with pytest.raises(ProtocolError, match="does not match"):
        Client(MockTransport([_result_body(request_id=2)])).plan({"template_name": "t"})


def test_rpc_error_preserves_code_and_data():
    body = json.dumps(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "error": {
                "code": -32601,
                "message": "method not found",
                "data": {"type": "method_not_found", "step": "s"},
            },
        }
    )
    with pytest.raises(RpcError) as caught:
        Client(MockTransport([body])).plan({"template_name": "t"})
    assert caught.value.code == -32601
    assert caught.value.message == "method not found"
    assert caught.value.data["type"] == "method_not_found"
    assert caught.value.step == "s"


def test_timeout_is_a_transport_error_not_an_rpc_error():
    with pytest.raises(TransportError) as caught:
        Client(RaisingTransport(socket.timeout("timed out"))).plan({"template_name": "t"})
    assert not isinstance(caught.value, RpcError)


def test_mock_transport_exhausted():
    with pytest.raises(TransportError):
        Client(MockTransport()).plan({"template_name": "t"})


def test_invalid_json_is_a_protocol_error():
    with pytest.raises(ProtocolError):
        Client(MockTransport(["not-json"])).plan({"template_name": "t"})


def test_missing_result_is_a_protocol_error():
    body = json.dumps({"jsonrpc": "2.0", "id": 1})
    with pytest.raises(ProtocolError):
        Client(MockTransport([body])).plan({"template_name": "t"})


def test_notification_has_no_id():
    transport = MockTransport([""])
    Client(transport).notify("rigorix.audit.read", {"execution_id": "e"})
    sent = json.loads(transport.requests[0])
    assert sent["method"] == "rigorix.audit.read"
    assert "id" not in sent


def test_batch_preserves_success_and_error():
    body = json.dumps(
        [
            {"jsonrpc": "2.0", "id": 1, "result": {}},
            {"jsonrpc": "2.0", "id": 2, "error": {"code": -32601, "message": "nope"}},
        ]
    )
    responses = Client(MockTransport([body])).batch_raw(
        [BatchCall("rigorix.audit.list"), BatchCall("rigorix.template.list")]
    )
    assert len(responses) == 2
    assert responses[0]["result"] == {}
    assert responses[1]["error"]["code"] == -32601


def test_catalog_parity_with_frozen_catalog():
    frozen = {
        method["name"]
        for method in json.loads(corpus.schema_text("api/catalog.json"))["methods"]
    }
    assert set(catalog.METHODS) == frozen
    assert len(catalog.TYPED_METHODS) == 18
    assert set(catalog.TYPED_METHODS).isdisjoint(catalog.SERVER_ONLY_METHODS)


def test_client_adds_no_dependency():
    """The client is stdlib-only: the runtime deps are the binding's, not its.

    Names, not versions: an exact runtime pin (SDL-5) must not fail this test.
    """
    text = (Path(__file__).resolve().parents[1] / "pyproject.toml").read_text(encoding="utf-8")
    assert "requests" not in text and "httpx" not in text
    names = set(re.findall(r'"([A-Za-z0-9_.-]+)\s*(?:[<>=!~]|")', text.split("dependencies = [")[1].split("]")[0]))
    assert names == {"jsonschema", "cryptography", "wasmtime"}


@pytest.fixture
def rpc_server():
    """HTTP/1.1 with keep-alive, a connection count, and optional misbehaviour.

    `handler.connections` counts accepted connections, which is how the tests
    tell "the pool reused a socket" from "the pool opened another one".
    """

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        status = 200
        body = _version_body()
        close_after_response = False
        hang_seconds = 0.0
        connections = 0

        def setup(self):  # noqa: D401 (http.server hook)
            super().setup()
            type(self).connections += 1

        def do_POST(self):  # noqa: N802 (http.server naming)
            length = int(self.headers.get("content-length", "0"))
            request = json.loads(self.rfile.read(length) or b"{}")
            if self.hang_seconds:
                time.sleep(self.hang_seconds)
            # Echo the request id: the client is entitled to reject a mismatch,
            # and two pooled calls carry different ids.
            body = self.body
            if self.status == 200 and self.body == _version_body():
                body = _version_body(request_id=request.get("id"))
            payload = body.encode("utf-8")
            self.send_response(self.status)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(payload)))
            if self.close_after_response:
                self.send_header("connection", "close")
            self.end_headers()
            self.wfile.write(payload)
            if self.close_after_response:
                self.close_connection = True

        def log_message(self, *args):  # noqa: ARG002
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server, Handler
    finally:
        server.shutdown()
        thread.join()
        server.server_close()


def test_http_transport(rpc_server):
    server, _ = rpc_server
    url = f"http://127.0.0.1:{server.server_port}/rpc"
    version = Client(HTTPTransport(url)).version()
    assert version["api_version"] == "1.0.0"


def test_http_transport_reuses_one_connection(rpc_server):
    """Two calls, one socket: the point of the change (#140).

    A fresh connection per call cost ~0.18 ms over a reusable one — 2× the
    whole client call on localhost, where connection setup is the entire cost.
    """
    server, handler = rpc_server
    url = f"http://127.0.0.1:{server.server_port}/rpc"
    transport = HTTPTransport(url)
    client = Client(transport)
    try:
        client.version()
        client.version()
        assert handler.connections == 1, (
            f"the transport opened {handler.connections} connections for 2 calls"
        )
    finally:
        transport.close()


def test_http_transport_reconnects_after_an_idle_close(rpc_server):
    """A server may close a keep-alive connection; that is not an answer."""
    server, handler = rpc_server
    handler.close_after_response = True
    url = f"http://127.0.0.1:{server.server_port}/rpc"
    transport = HTTPTransport(url)
    try:
        client = Client(transport)
        client.version()
        # The server closed the socket after answering; the second call must
        # notice, reconnect and still answer rather than raising.
        client.version()
        assert handler.connections == 2
    finally:
        transport.close()


def test_http_transport_is_safe_across_threads(rpc_server):
    """One socket, many callers: the pool serialises, it does not interleave.

    `urlopen` per call was incidentally thread-safe. A shared connection is
    not, unless the request/response pair is atomic — and a JSON-RPC body
    interleaved with another call's is a corrupt request, not a slow one.
    """
    server, handler = rpc_server
    url = f"http://127.0.0.1:{server.server_port}/rpc"
    transport = HTTPTransport(url)
    client = Client(transport)
    errors = []

    def worker():
        try:
            for _ in range(5):
                assert client.version()["api_version"] == "1.0.0"
        except Exception as exc:  # noqa: BLE001 - the failure is the assertion
            errors.append(exc)

    threads = [threading.Thread(target=worker) for _ in range(4)]
    try:
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
    finally:
        transport.close()

    assert not errors, errors
    # 20 calls: the pool may have reconnected, but it must not have opened a
    # connection per call.
    assert handler.connections < 20, f"{handler.connections} connections for 20 calls"


def test_http_transport_timeout_still_bounds_the_read(rpc_server):
    """Pooling must not lose the per-call bound a hung server needs.

    `urlopen(timeout=…)` bounded the read, not just the connect; a pooled
    connection that only bounded the connect would hang here forever.
    """
    server, handler = rpc_server
    handler.hang_seconds = 0.6
    url = f"http://127.0.0.1:{server.server_port}/rpc"
    transport = HTTPTransport(url, timeout=0.1)
    try:
        with pytest.raises(TransportError, match="timeout"):
            Client(transport).version()
    finally:
        transport.close()


def test_http_transport_rejects_a_url_it_cannot_pool():
    with pytest.raises(ValueError, match="not http"):
        HTTPTransport("tcp://127.0.0.1:9000/rpc")
    with pytest.raises(ValueError, match="no host"):
        HTTPTransport("http:///rpc")


def test_http_transport_non_2xx_is_a_transport_error(rpc_server):
    server, handler = rpc_server
    handler.status = 500
    url = f"http://127.0.0.1:{server.server_port}/rpc"
    with pytest.raises(TransportError):
        Client(HTTPTransport(url)).plan({"template_name": "t"})


def test_live_version():
    url = os.environ.get("RIGORIX_SERVER_URL")
    if not url:
        pytest.skip("RIGORIX_SERVER_URL not set")
    version = Client(HTTPTransport(url)).version()
    assert version["api_version"].startswith("1.")
