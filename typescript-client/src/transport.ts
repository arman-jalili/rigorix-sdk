/** Transport seam — the crate depends on no HTTP framework. */

import { TransportError } from "./error.js";

export interface Transport {
  /** POST a JSON-RPC body and return the raw response body. */
  post(body: string): Promise<string>;
}

/** A `fetch`-based transport (Node 20+ has a global `fetch`). */
export class FetchTransport implements Transport {
  constructor(
    private readonly url: string,
    private readonly headers: Record<string, string> = {},
  ) {}

  async post(body: string): Promise<string> {
    const response = await fetch(this.url, {
      method: "POST",
      headers: { "content-type": "application/json", ...this.headers },
      body,
    });
    if (!response.ok) {
      throw new TransportError(`transport: HTTP ${response.status}`);
    }
    return response.text();
  }
}

/** A test transport that records requests and replays queued responses. */
export class MockTransport implements Transport {
  readonly requests: string[] = [];

  constructor(private readonly responses: string[] = []) {}

  async post(body: string): Promise<string> {
    this.requests.push(body);
    const response = this.responses.shift();
    if (response === undefined) {
      throw new TransportError("mock transport: no queued response");
    }
    return response;
  }
}
