/** Error taxonomy mapping (`schemas/api/errors.json`, ADR-0001 D6).
 *
 * `data.type` is the stable machine identifier. Every declared type maps to a
 * distinct `ApiError.kind`; an unknown type falls through to `"unknown"` —
 * never a throw. */

export const API_ERROR_TYPES = [
  "parse_error",
  "invalid_request",
  "method_not_found",
  "invalid_params",
  "internal_error",
  "not_authenticated",
  "insufficient_scope",
  "denied_by_sequence",
  "policy_violation",
  "approval_required",
  "identity_required",
  "budget_exhausted",
  "timeout",
  "api_error",
  "not_enabled",
] as const;

export type ApiErrorType = (typeof API_ERROR_TYPES)[number];

/** The stable `data.type` value for a typed error, or `"unknown"`. */
export class ApiError extends Error {
  readonly kind: ApiErrorType | "unknown";
  readonly type: string;
  readonly code?: number;
  readonly data?: unknown;

  constructor(type: string, message: string, code?: number, data?: unknown) {
    super(`${type}: ${message}`);
    this.name = "ApiError";
    this.type = type;
    this.kind = (API_ERROR_TYPES as readonly string[]).includes(type)
      ? (type as ApiErrorType)
      : "unknown";
    this.code = code;
    this.data = data;
  }

  /** `data.rule_id`, when present (`denied_by_sequence`). */
  get ruleId(): string | undefined {
    const value = (this.data as Record<string, unknown> | undefined)?.rule_id;
    return typeof value === "string" ? value : undefined;
  }

  /** `data.step`, when present (`denied_by_sequence`). */
  get step(): string | undefined {
    const value = (this.data as Record<string, unknown> | undefined)?.step;
    return typeof value === "string" ? value : undefined;
  }
}

/** The JSON-RPC `error` object shape. */
export interface RpcErrorShape {
  code: number;
  message: string;
  data?: { type?: string; [key: string]: unknown };
}

/** Base class for every client-side failure. */
export class ClientError extends Error {}

/** The transport failed (network/IO or non-2xx). */
export class TransportError extends ClientError {}

/** A malformed JSON-RPC response (neither `result` nor `error`). */
export class ProtocolError extends ClientError {}

/** A JSON-RPC `error` object, mapped to the typed taxonomy. */
export class JsonRpcError extends ClientError {
  constructor(readonly rpc: RpcErrorShape) {
    super(`json-rpc error ${rpc.code}: ${rpc.message}`);
    this.name = "JsonRpcError";
  }

  get apiError(): ApiError {
    const data = this.rpc.data;
    const type = typeof data?.type === "string" ? data.type : "unknown";
    return new ApiError(type, this.rpc.message, this.rpc.code, data);
  }
}

/** The server's `api_version` is incompatible with this client's major. */
export class VersionMismatchError extends ClientError {
  constructor(
    readonly server: string,
    readonly clientMajor: number,
  ) {
    super(
      `server apiVersion ${server} is incompatible with the client constraint (major ${clientMajor})`,
    );
    this.name = "VersionMismatchError";
  }
}
