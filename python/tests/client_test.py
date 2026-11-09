"""Protocol client against the frozen catalog (SDL-2)."""

from __future__ import annotations

import http.server
import json
import os
import re
import socket
import threading
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
    class Handler(http.server.BaseHTTPRequestHandler):
        status = 200
        body = _version_body()

        def do_POST(self):  # noqa: N802 (http.server naming)
            length = int(self.headers.get("content-length", "0"))
            self.rfile.read(length)
            self.send_response(self.status)
            self.send_header("content-type", "application/json")
            self.end_headers()
            self.wfile.write(self.body.encode("utf-8"))

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
