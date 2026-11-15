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
    CommandMayHaveExecuted,
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


#: Every typed method, the call that reaches it, and whether a repetition of that
#: call is safe (#144). The third column is the specification: a new method has to
#: state its answer here, and `False` is what an undeclared one gets.
TYPED_CALLS = [
    ("rigorix.plan", lambda c: c.plan({"template_name": "t"}), False),
    ("rigorix.validatePlan", lambda c: c.validate_plan({"plan": {}}), True),
    ("rigorix.run", lambda c: c.run({"template_name": "t"}), False),
    ("rigorix.execute", lambda c: c.execute({"template_name": "t"}), False),
    ("rigorix.approve", lambda c: c.approve({"execution_id": "e", "step_names": ["s"]}), False),
    ("rigorix.checkEnforcement", lambda c: c.check_enforcement(), True),
    ("rigorix.audit.read", lambda c: c.audit_read({"execution_id": "e"}), True),
    ("rigorix.audit.list", lambda c: c.audit_list({}), True),
    ("rigorix.audit.summary", lambda c: c.audit_summary({}), True),
    ("rigorix.template.list", lambda c: c.template_list({}), True),
    ("rigorix.template.get", lambda c: c.template_get({"name": "t"}), True),
    ("rigorix.template.create", lambda c: c.template_create({"name": "t", "plan": {}}), False),
    ("rigorix.template.validate", lambda c: c.template_validate({"plan": {}}), True),
    ("rigorix.auth.login", lambda c: c.auth_login({}), False),
    ("rigorix.auth.status", lambda c: c.auth_status(), True),
    ("rigorix.auth.logout", lambda c: c.auth_logout(), False),
    ("rigorix.usageGuide", lambda c: c.usage_guide(), True),
    ("rigorix.system.version", lambda c: c.version(), True),
]


def test_all_typed_methods_send_the_frozen_names():
    assert len(TYPED_CALLS) == 18

    for method, invoke, _ in TYPED_CALLS:
        body = _version_body() if method == "rigorix.system.version" else _result_body()
        transport = MockTransport([body])
        invoke(Client(transport))
        sent = json.loads(transport.requests[0])
        assert sent["jsonrpc"] == "2.0"
        assert sent["method"] == method


def test_every_typed_method_declares_whether_a_repeat_is_safe():
    """#144: the declaration is per call site, and the safe answer is the default."""
    for method, invoke, idempotent in TYPED_CALLS:
        body = _version_body() if method == "rigorix.system.version" else _result_body()
        transport = MockTransport([body])
        invoke(Client(transport))
        assert transport.idempotent_flags == [idempotent], (
            f"{method} declared idempotent={transport.idempotent_flags[0]}, "
            f"the specification says {idempotent}"
        )


def test_a_notification_and_a_batch_are_never_declared_idempotent():
    transport = MockTransport([_result_body(), "[]"])
    client = Client(transport)
    client.notify("rigorix.audit.read", {"execution_id": "e"})
    client.batch_raw([BatchCall("rigorix.audit.list")])
    assert transport.idempotent_flags == [False, False]


def test_a_transport_without_the_keyword_still_works():
    """The keyword is optional in the protocol: an older transport is usable.

    `RaisingTransport` predates #144 and takes only `body`; the client must not
    pass a keyword it cannot accept, and must not refuse to call it.
    """

    class LegacyTransport:
        def __init__(self):
            self.requests = []

        def post(self, body):
            self.requests.append(body)
            return _version_body()

    legacy = LegacyTransport()
    assert Client(legacy).version()["api_version"] == "1.0.0"
    assert len(legacy.requests) == 1


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
        #: Announce the close (`connection: close`) and honour it.
        close_after_response = False
        #: Drop the socket after answering *without* announcing it: the stale
        #: keep-alive connection a real proxy or idle timeout leaves behind, which
        #: is the only case where the client discovers the close mid-request.
        drop_after_response = False
        hang_seconds = 0.0
        #: Refuse (answer and close) every connection after the first N: this is
        #: how a test makes the *retry* fail, so "retried exactly once" is
        #: measurable rather than assumed.
        refuse_after_connections = 0
        connections = 0
        requests = 0

        def setup(self):  # noqa: D401 (http.server hook)
            super().setup()
            type(self).connections += 1

        def do_POST(self):  # noqa: N802 (http.server naming)
            type(self).requests += 1
            length = int(self.headers.get("content-length", "0"))
            request = json.loads(self.rfile.read(length) or b"{}")
            if self.hang_seconds:
                time.sleep(self.hang_seconds)
            if self.refuse_after_connections and self.connections > self.refuse_after_connections:
                # Say nothing and close: the client sees the connection fail, not
                # an answer. This is the shape a retry must survive once.
                self.close_connection = True
                return
            # Echo the request id: the client is entitled to reject a mismatch,
            # and two pooled calls carry different ids. Any result shape that
            # carries an `id` is echoed, so a `run` payload keeps its id too.
            body = self.body
            if self.status == 200:
                try:
                    parsed = json.loads(self.body)
                except ValueError:
                    parsed = None
                if isinstance(parsed, dict) and "id" in parsed:
                    parsed["id"] = request.get("id")
                    body = json.dumps(parsed)
            payload = body.encode("utf-8")
            self.send_response(self.status)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(payload)))
            if self.close_after_response:
                self.send_header("connection", "close")
            self.end_headers()
            self.wfile.write(payload)
            if self.close_after_response or self.drop_after_response:
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
        # Announced close: `http.client` sees `connection: close`, so the second
        # call opens a fresh connection *before* writing and no request is lost —
        # one request per call. The unannounced drop is the retry's business.
        assert handler.requests == 2
    finally:
        transport.close()


def test_a_read_is_retried_once_after_an_unannounced_close(rpc_server):
    """The retry's own subject: the server drops the socket without saying so.

    Nothing tells the client the connection is gone, so the next request is
    written into a dead socket and the answer never arrives. For a declared read
    that is not an answer: one re-send, on a fresh connection, and the call
    still succeeds.
    """
    server, handler = rpc_server
    handler.drop_after_response = True
    url = f"http://127.0.0.1:{server.server_port}/rpc"
    transport = HTTPTransport(url)
    try:
        client = Client(transport)
        client.version()
        assert client.version()["api_version"] == "1.0.0"
        assert handler.connections == 2, (
            f"{handler.connections} connections: the retry must open exactly one"
        )
        # The lost attempt reached nobody; the retry is the only request the
        # server saw for the second call.
        assert handler.requests == 2
    finally:
        transport.close()


def test_a_command_is_sent_once_and_the_error_says_it_may_have_executed(rpc_server):
    """#144: `run` is never retried, and the failure carries the risk.

    The server closes the socket after answering, so the next `run` fails on a
    reused connection — the exact case the read path retries. For a command the
    body may already have reached the server, so a re-send could be a second
    execution. One connection is the assertion: a retry would open a second.
    """
    server, handler = rpc_server
    handler.drop_after_response = True
    handler.body = json.dumps(
        {"jsonrpc": "2.0", "id": 1, "result": {"status": "completed", "envelope": "e1"}}
    )
    url = f"http://127.0.0.1:{server.server_port}/rpc"
    transport = HTTPTransport(url)
    try:
        client = Client(transport)
        assert client.run({"template_name": "t", "execution_id": "exec-1"})["status"] == "completed"
        with pytest.raises(CommandMayHaveExecuted) as caught:
            client.run({"template_name": "t", "execution_id": "exec-1"})
        assert caught.value.may_have_executed is True
        message = str(caught.value)
        assert "may have executed" in message
        assert "execution_id" in message and "audit.read" in message
        # No retry: the transport never opened a second connection, so the second
        # call was one attempt — and at most one execution reached the server.
        assert handler.connections == 1, f"{handler.connections} connections for 2 commands"
        assert handler.requests <= 2
    finally:
        transport.close()


def test_a_command_that_timed_out_may_have_executed(rpc_server):
    """A hung answer is as ambiguous as a closed socket: the run may have finished."""
    server, handler = rpc_server
    handler.hang_seconds = 0.6
    url = f"http://127.0.0.1:{server.server_port}/rpc"
    transport = HTTPTransport(url, timeout=0.1)
    try:
        with pytest.raises(CommandMayHaveExecuted, match="did not arrive within"):
            Client(transport).run({"template_name": "t"})
    finally:
        transport.close()


def test_a_failure_before_the_body_leaves_is_not_a_command_risk():
    """Nothing listened, so nothing ran: resending is safe, and the flag says so."""
    transport = HTTPTransport("http://127.0.0.1:1/rpc", timeout=2.0)
    with pytest.raises(TransportError) as caught:
        Client(transport).run({"template_name": "t"})
    assert caught.value.may_have_executed is False
    assert not isinstance(caught.value, CommandMayHaveExecuted)
    transport.close()


def test_a_retried_read_propagates_its_second_failure(rpc_server):
    """Retried exactly once: the retry's own failure is the caller's answer."""
    server, handler = rpc_server
    handler.drop_after_response = True
    # The connection the retry lands on answers nothing at all.
    handler.refuse_after_connections = 1
    url = f"http://127.0.0.1:{server.server_port}/rpc"
    transport = HTTPTransport(url)
    try:
        client = Client(transport)
        client.version()
        with pytest.raises(TransportError) as caught:
            client.version()
        # A read that failed twice is a transport failure, not a command risk.
        assert not isinstance(caught.value, CommandMayHaveExecuted)
        assert handler.connections == 2, (
            f"{handler.connections} connections: the retry must happen once, not loop"
        )
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
