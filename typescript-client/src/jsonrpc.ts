/** JSON-RPC 2.0 framing (ADR-0001 D1): single requests, batch arrays, and
 * notifications (requests with no `id`). */

import type { RpcErrorShape } from "./error.js";

export interface RpcRequest {
  jsonrpc: "2.0";
  method: string;
  params?: unknown;
  id?: number | string;
}

export interface RpcResponse {
  jsonrpc?: string;
  id?: number | string;
  result?: unknown;
  error?: RpcErrorShape;
}

/** A request expecting a response. */
export function call(id: number | string, method: string, params?: unknown): RpcRequest {
  return { jsonrpc: "2.0", method, params, id };
}

/** A notification — no `id`, no response expected. */
export function notification(method: string, params?: unknown): RpcRequest {
  return { jsonrpc: "2.0", method, params };
}

export function encode(request: RpcRequest): string {
  return JSON.stringify(request);
}

export function encodeBatch(requests: RpcRequest[]): string {
  return JSON.stringify(requests);
}

export function decode<T = RpcResponse>(body: string): T {
  return JSON.parse(body) as T;
}

export function decodeBatch(body: string): RpcResponse[] {
  return JSON.parse(body) as RpcResponse[];
}
