"""Typed JSON-RPC client over the frozen ``rigorix.*`` catalog."""

from __future__ import annotations

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

    def _id(self) -> int:
        value = self._next_id
        self._next_id += 1
        return value

    def call_raw(self, method: str, params: Any = None) -> Any:
        """Call a method and return the raw ``result`` value."""
        request_id = self._id()
        body = encode(call(request_id, method, params))
        try:
            response_body = self._transport.post(body)
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

    def call(self, method: str, params: Any = None) -> Any:
        """Alias for :meth:`call_raw` (parity with the TS client)."""
        return self.call_raw(method, params)

    def notify(self, method: str, params: Any = None) -> None:
        """Send a notification (no ``id``; no response expected)."""
        body = encode(notification(method, params))
        try:
            self._transport.post(body)
        except TransportError:
            raise
        except (OSError, TimeoutError) as exc:
            raise TransportError(f"transport: {exc}") from exc

    def batch_raw(self, calls: Sequence[BatchCall]) -> List[Dict[str, Any]]:
        """Send a batch (one JSON array) and return the raw responses."""
        requests = [call(self._id(), entry.method, entry.params) for entry in calls]
        body = encode_batch(requests)
        try:
            response_body = self._transport.post(body)
        except TransportError:
            raise
        except (OSError, TimeoutError) as exc:
            raise TransportError(f"transport: {exc}") from exc
        return decode_batch(response_body)

    # ─── Governed flows ──────────────────────────────────────────────────

    def plan(self, params: catalog.PlanParams) -> catalog.PlanResult:
        return cast(catalog.PlanResult, self.call_raw("rigorix.plan", params))

    def validate_plan(self, params: catalog.ValidatePlanParams) -> catalog.ValidateResult:
        return cast(catalog.ValidateResult, self.call_raw("rigorix.validatePlan", params))

    def run(self, params: catalog.RunParams) -> catalog.ExecuteResult:
        return cast(catalog.ExecuteResult, self.call_raw("rigorix.run", params))

    def execute(self, params: catalog.ExecuteParams) -> catalog.ExecuteResult:
        return cast(catalog.ExecuteResult, self.call_raw("rigorix.execute", params))

    def approve(self, params: catalog.ApproveParams) -> catalog.ApproveResult:
        return cast(catalog.ApproveResult, self.call_raw("rigorix.approve", params))

    def check_enforcement(self) -> catalog.CheckEnforcementResult:
        return cast(
            catalog.CheckEnforcementResult,
            self.call_raw("rigorix.checkEnforcement", {}),
        )

    # ─── Audit (read side) ───────────────────────────────────────────────

    def audit_read(self, params: catalog.AuditReadParams) -> catalog.AuditReadResult:
        return cast(catalog.AuditReadResult, self.call_raw("rigorix.audit.read", params))

    def audit_list(self, params: catalog.AuditListParams) -> catalog.AuditListResult:
        return cast(catalog.AuditListResult, self.call_raw("rigorix.audit.list", params))

    def audit_summary(self, params: catalog.AuditSummaryParams) -> catalog.AuditSummaryResult:
        return cast(
            catalog.AuditSummaryResult,
            self.call_raw("rigorix.audit.summary", params),
        )

    # ─── Templates ───────────────────────────────────────────────────────

    def template_list(self, params: catalog.TemplateListParams) -> catalog.TemplateListResult:
        return cast(
            catalog.TemplateListResult,
            self.call_raw("rigorix.template.list", params),
        )

    def template_get(self, params: catalog.TemplateGetParams) -> catalog.TemplateGetResult:
        return cast(catalog.TemplateGetResult, self.call_raw("rigorix.template.get", params))

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
            self.call_raw("rigorix.template.validate", params),
        )

    # ─── Auth (device flow) ──────────────────────────────────────────────

    def auth_login(self, params: catalog.AuthLoginParams) -> catalog.AuthLoginResult:
        return cast(catalog.AuthLoginResult, self.call_raw("rigorix.auth.login", params))

    def auth_status(self) -> catalog.AuthStatusResult:
        return cast(catalog.AuthStatusResult, self.call_raw("rigorix.auth.status", {}))

    def auth_logout(self) -> catalog.AuthLogoutResult:
        return cast(catalog.AuthLogoutResult, self.call_raw("rigorix.auth.logout", {}))

    # ─── Self-description / negotiation ──────────────────────────────────

    def usage_guide(self) -> catalog.UsageGuideResult:
        return cast(catalog.UsageGuideResult, self.call_raw("rigorix.usageGuide", {}))

    def version(self) -> catalog.VersionResult:
        version = cast(
            catalog.VersionResult,
            self.call_raw("rigorix.system.version", {}),
        )
        major = _api_major(version["api_version"])
        if major != catalog.CLIENT_API_MAJOR:
            raise IncompatibleVersion(version["api_version"], catalog.CLIENT_API_MAJOR)
        return version


def _api_major(version: str) -> int:
    head = version.split(".", 1)[0]
    if head.startswith("v"):
        head = head[1:]
    try:
        return int(head)
    except ValueError as exc:
        raise ProtocolError(f"invalid api_version {version!r}") from exc
