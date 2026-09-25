/** The typed client over a `Transport` (ADR-0001 D1/D3). */

import {
  ClientError,
  JsonRpcError,
  ProtocolError,
  VersionMismatchError,
} from "./error.js";
import {
  call,
  decode,
  decodeBatch,
  encode,
  encodeBatch,
  notification,
  type RpcResponse,
} from "./jsonrpc.js";
import type { Transport } from "./transport.js";
import type * as types from "./types.js";

/** The native API major this client targets (catalog.json `apiVersion`). */
export const CLIENT_API_MAJOR = 1;
/** The full native API version this client was built against. */
export const CLIENT_API_VERSION = "1.0.0";

/** One raw call in a batch. */
export class BatchCall {
  constructor(
    readonly method: string,
    readonly params?: unknown,
  ) {}
}

/** A typed JSON-RPC client over the frozen `rigorix.*` catalog. */
export class Client {
  private nextId = 1;

  constructor(private readonly transport: Transport) {}

  private id(): number {
    return this.nextId++;
  }

  /** Call a method and return the raw `result` value. */
  async callRaw(method: string, params?: unknown): Promise<unknown> {
    const body = encode(call(this.id(), method, params));
    const responseBody = await this.transport.post(body);
    const response = decode<RpcResponse>(responseBody);
    if (response.error) throw new JsonRpcError(response.error);
    if (response.result === undefined) {
      throw new ProtocolError("response has neither `result` nor `error`");
    }
    return response.result;
  }

  /** Call a method with typed params, returning a typed result. */
  async call<P, R>(method: string, params: P): Promise<R> {
    return (await this.callRaw(method, params)) as R;
  }

  /** Send a notification (no `id`; no response expected). */
  async notify(method: string, params?: unknown): Promise<void> {
    await this.transport.post(encode(notification(method, params)));
  }

  /** Send a batch (one JSON array) and return the raw responses. */
  async batchRaw(calls: BatchCall[]): Promise<RpcResponse[]> {
    const body = encodeBatch(calls.map((entry) => call(this.id(), entry.method, entry.params)));
    const responseBody = await this.transport.post(body);
    return decodeBatch(responseBody);
  }

  // ─── Governed flows ──────────────────────────────────────────────────

  plan(params: types.PlanParams): Promise<types.PlanResult> {
    return this.call("rigorix.plan", params);
  }

  validatePlan(params: types.ValidatePlanParams): Promise<types.ValidateResult> {
    return this.call("rigorix.validatePlan", params);
  }

  run(params: types.RunParams): Promise<types.ExecuteResult> {
    return this.call("rigorix.run", params);
  }

  execute(params: types.ExecuteParams): Promise<types.ExecuteResult> {
    return this.call("rigorix.execute", params);
  }

  approve(params: types.ApproveParams): Promise<types.ApproveResult> {
    return this.call("rigorix.approve", params);
  }

  checkEnforcement(): Promise<types.CheckEnforcementResult> {
    return this.call("rigorix.checkEnforcement", {});
  }

  // ─── Audit (read side) ───────────────────────────────────────────────

  auditRead(params: types.AuditReadParams): Promise<types.AuditReadResult> {
    return this.call("rigorix.audit.read", params);
  }

  auditList(params: types.AuditListParams): Promise<types.AuditListResult> {
    return this.call("rigorix.audit.list", params);
  }

  auditSummary(params: types.AuditSummaryParams): Promise<types.AuditSummaryResult> {
    return this.call("rigorix.audit.summary", params);
  }

  // ─── Templates ───────────────────────────────────────────────────────

  templateList(params: types.TemplateListParams): Promise<types.TemplateListResult> {
    return this.call("rigorix.template.list", params);
  }

  templateGet(params: types.TemplateGetParams): Promise<types.TemplateGetResult> {
    return this.call("rigorix.template.get", params);
  }

  templateCreate(params: types.TemplateCreateParams): Promise<types.TemplateCreateResult> {
    return this.call("rigorix.template.create", params);
  }

  templateValidate(params: types.TemplateValidateParams): Promise<types.ValidateResult> {
    return this.call("rigorix.template.validate", params);
  }

  // ─── Auth (device flow) ──────────────────────────────────────────────

  authLogin(params: types.AuthLoginParams): Promise<types.AuthLoginResult> {
    return this.call("rigorix.auth.login", params);
  }

  authStatus(): Promise<types.AuthStatusResult> {
    return this.call("rigorix.auth.status", {});
  }

  authLogout(): Promise<types.AuthLogoutResult> {
    return this.call("rigorix.auth.logout", {});
  }

  // ─── Self-description / negotiation ──────────────────────────────────

  usageGuide(): Promise<types.UsageGuideResult> {
    return this.call("rigorix.usageGuide", {});
  }

  async version(): Promise<types.VersionResult> {
    const version = await this.call<unknown, types.VersionResult>("rigorix.system.version", {});
    this.checkVersion(version);
    return version;
  }

  /** Verify the server's `api_version` is compatible with this client's major. */
  checkVersion(version: types.VersionResult): void {
    const major = Number.parseInt(version.api_version.split(".")[0] ?? "", 10);
    if (major !== CLIENT_API_MAJOR) {
      throw new VersionMismatchError(version.api_version, CLIENT_API_MAJOR);
    }
  }
}

export { ClientError };
