"""Typed JSON-RPC client over the frozen ``rigorix.*`` catalog."""

from __future__ import annotations

import inspect
from typing import Any, Dict, List, Sequence, cast

from . import catalog
from .error import IncompatibleVersion, ProtocolError, RpcError, TransportError
from .jsonrpc import call, decode, decode_batch, encode, encode_batch, notification
from .transport import Transport


class BatchCall:
    """One raw call in a batch."""

    def __init__(self, method: str, params: Any = None) -> None:
        self.method = method
        self.params = params


class Client:
    """A typed client over a ``Transport``.

    ``call_raw`` rejects a response whose ``id`` is not the request's; a
    transport timeout/IO failure is a ``TransportError`` (the host did not
    answer), never an ``RpcError`` (the host refused).
    """

    def __init__(self, transport: Transport) -> None:
        self._transport = transport
        self._next_id = 1
        # A transport written before #144 has `post(body)`. Passing an unknown
        # keyword to it would be a TypeError at call time, so ask once.
        self._declares_idempotency = _accepts_keyword(transport.post, "idempotent")

    def _post(self, body: str, idempotent: bool) -> str:
        """Hand the body to the transport with the caller's declaration.

        A transport that cannot accept the keyword is used as-is: the client
        cannot enforce a retry policy inside a transport it does not own, and
        refusing to work with one would be a breaking change for a keyword
        whose default is the safe answer.
        """
        if self._declares_idempotency:
            return self._transport.post(body, idempotent=idempotent)
        return self._transport.post(body)

    def _id(self) -> int:
        value = self._next_id
        self._next_id += 1
        return value

    def call_raw(self, method: str, params: Any = None, *, idempotent: bool = False) -> Any:
        """Call a method and return the raw ``result`` value.

        ``idempotent`` says a repeated send cannot produce a second effect; the
        transport retries only a declared call, and raises
        :class:`~.error.CommandMayHaveExecuted` instead for the others (#144).
        It defaults to ``False``: a method added here and not classified is
        treated as a command, which is the safe answer.
        """
        request_id = self._id()
        body = encode(call(request_id, method, params))
        try:
            response_body = self._post(body, idempotent)
        except TransportError:
            raise
        except (OSError, TimeoutError) as exc:
            raise TransportError(f"transport: {exc}") from exc

        response = decode(response_body)
        error = response.get("error")
        if error is not None:
            code = error.get("code", 0)
            message = error.get("message", "")
            raise RpcError(
                code if isinstance(code, int) else 0,
                message if isinstance(message, str) else str(message),
                error.get("data"),
            )
        if response.get("id") != request_id:
            raise ProtocolError(
                f"response id {response.get('id')!r} does not match request id {request_id!r}"
            )
        if "result" not in response:
            raise ProtocolError("response has neither `result` nor `error`")
        return response["result"]

    def call(self, method: str, params: Any = None, *, idempotent: bool = False) -> Any:
        """Alias for :meth:`call_raw` (parity with the TS client)."""
        return self.call_raw(method, params, idempotent=idempotent)

    def notify(self, method: str, params: Any = None) -> None:
        """Send a notification (no ``id``; no response expected)."""
        body = encode(notification(method, params))
        # A notification gets no answer, so a retry would be indistinguishable
        # from a second request: never retried, and never claimed idempotent.
        try:
            self._post(body, False)
        except TransportError:
            raise
        except (OSError, TimeoutError) as exc:
            raise TransportError(f"transport: {exc}") from exc

    def batch_raw(self, calls: Sequence[BatchCall]) -> List[Dict[str, Any]]:
        """Send a batch (one JSON array) and return the raw responses."""
        requests = [call(self._id(), entry.method, entry.params) for entry in calls]
        body = encode_batch(requests)
        # A batch can mix a read with a command, and the declaration is per
        # call: unless every member is safe to repeat, the batch is not.
        try:
            response_body = self._post(body, False)
        except TransportError:
            raise
        except (OSError, TimeoutError) as exc:
            raise TransportError(f"transport: {exc}") from exc
        return decode_batch(response_body)

    # ─── Governed flows ──────────────────────────────────────────────────

    def plan(self, params: catalog.PlanParams) -> catalog.PlanResult:
        """Resolve a template to a planned DAG.

        Not declared idempotent, deliberately: the catalog says it resolves and
        pre-flights, not that it writes nothing, and a method the SDK cannot
        classify is treated as a command. If a measurement shows `plan` leaves
        no record, this is the line that changes (#144).
        """
        return cast(catalog.PlanResult, self.call_raw("rigorix.plan", params))

    def validate_plan(self, params: catalog.ValidatePlanParams) -> catalog.ValidateResult:
        return cast(
            catalog.ValidateResult,
            self.call_raw("rigorix.validatePlan", params, idempotent=True),
        )

    def run(self, params: catalog.RunParams) -> catalog.ExecuteResult:
        """Governed execution of a template's plan. Never retried.

        A transport failure on this call can mean the run executed and the
        answer was lost, so it raises
        :class:`~.error.CommandMayHaveExecuted` rather than re-sending — two
        envelopes for one call is the property the engine exists to prevent.

        What to do when that surfaces: supply ``execution_id`` in ``params`` so
        the attempt is identifiable, read ``rigorix.audit.read`` for it, and
        send again only after confirming no envelope exists. Whether a second
        ``run`` with the same ``execution_id`` refuses or resumes is a server
        property this client does not assume (#144).
        """
        return cast(catalog.ExecuteResult, self.call_raw("rigorix.run", params))

    def execute(self, params: catalog.ExecuteParams) -> catalog.ExecuteResult:
        """Governed execution of an explicit plan or template. Never retried; see
        :meth:`run` for what to do when the failure says it may have executed."""
        return cast(catalog.ExecuteResult, self.call_raw("rigorix.execute", params))

    def approve(self, params: catalog.ApproveParams) -> catalog.ApproveResult:
        """Approval bound to the attested session identity. Never retried: a
        re-sent approval is a second signature, not a repeat of the first."""
        return cast(catalog.ApproveResult, self.call_raw("rigorix.approve", params))

    def check_enforcement(self) -> catalog.CheckEnforcementResult:
        return cast(
            catalog.CheckEnforcementResult,
            self.call_raw("rigorix.checkEnforcement", {}, idempotent=True),
        )

    # ─── Audit (read side) ───────────────────────────────────────────────

    def audit_read(self, params: catalog.AuditReadParams) -> catalog.AuditReadResult:
        return cast(catalog.AuditReadResult, self.call_raw("rigorix.audit.read", params, idempotent=True))

    def audit_list(self, params: catalog.AuditListParams) -> catalog.AuditListResult:
        return cast(catalog.AuditListResult, self.call_raw("rigorix.audit.list", params, idempotent=True))

    def audit_summary(self, params: catalog.AuditSummaryParams) -> catalog.AuditSummaryResult:
        return cast(
            catalog.AuditSummaryResult,
            self.call_raw("rigorix.audit.summary", params, idempotent=True),
        )

    # ─── Templates ───────────────────────────────────────────────────────

    def template_list(self, params: catalog.TemplateListParams) -> catalog.TemplateListResult:
        return cast(
            catalog.TemplateListResult,
            self.call_raw("rigorix.template.list", params, idempotent=True),
        )

    def template_get(self, params: catalog.TemplateGetParams) -> catalog.TemplateGetResult:
        return cast(catalog.TemplateGetResult, self.call_raw("rigorix.template.get", params, idempotent=True))

    def template_create(
        self, params: catalog.TemplateCreateParams
    ) -> catalog.TemplateCreateResult:
        return cast(
            catalog.TemplateCreateResult,
            self.call_raw("rigorix.template.create", params),
        )

    def template_validate(
        self, params: catalog.TemplateValidateParams
    ) -> catalog.ValidateResult:
        return cast(
            catalog.ValidateResult,
            self.call_raw("rigorix.template.validate", params, idempotent=True),
        )

    # ─── Auth (device flow) ──────────────────────────────────────────────

    def auth_login(self, params: catalog.AuthLoginParams) -> catalog.AuthLoginResult:
        return cast(catalog.AuthLoginResult, self.call_raw("rigorix.auth.login", params))

    def auth_status(self) -> catalog.AuthStatusResult:
        return cast(catalog.AuthStatusResult, self.call_raw("rigorix.auth.status", {}, idempotent=True))

    def auth_logout(self) -> catalog.AuthLogoutResult:
        return cast(catalog.AuthLogoutResult, self.call_raw("rigorix.auth.logout", {}))

    # ─── Self-description / negotiation ──────────────────────────────────

    def usage_guide(self) -> catalog.UsageGuideResult:
        return cast(catalog.UsageGuideResult, self.call_raw("rigorix.usageGuide", {}, idempotent=True))

    def version(self) -> catalog.VersionResult:
        version = cast(
            catalog.VersionResult,
            self.call_raw("rigorix.system.version", {}, idempotent=True),
        )
        major = _api_major(version["api_version"])
        if major != catalog.CLIENT_API_MAJOR:
            raise IncompatibleVersion(version["api_version"], catalog.CLIENT_API_MAJOR)
        return version


# The idempotency of every typed method is declared at its own call site, not in
# a list beside them: a parallel table is a second copy of the fact, and the copy
# that must track the other is the defect (#126, #144). `tests/client_test.py`
# holds the expected classification as a specification, so adding a method
# without deciding is a test failure rather than a silent default.


def _accepts_keyword(method: Any, name: str) -> bool:
    """Whether ``method`` takes a keyword called ``name``."""
    try:
        parameters = inspect.signature(method).parameters
    except (TypeError, ValueError):
        # A C callable or a builtin: assume the shape this package documents.
        return False
    if any(p.kind is p.VAR_KEYWORD for p in parameters.values()):
        return True
    return name in parameters


def _api_major(version: str) -> int:
    head = version.split(".", 1)[0]
    if head.startswith("v"):
        head = head[1:]
    try:
        return int(head)
    except ValueError as exc:
        raise ProtocolError(f"invalid api_version {version!r}") from exc
