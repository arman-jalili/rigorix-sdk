import { strict as assert } from "node:assert";
import { test } from "node:test";

import { BatchCall, Client } from "../src/client.js";
import { JsonRpcError, ProtocolError, VersionMismatchError } from "../src/error.js";
import { MockTransport } from "../src/transport.js";

function response(id: number, result: unknown): string {
  return JSON.stringify({ jsonrpc: "2.0", id, result });
}

test("single call framing + typed result", async () => {
  const transport = new MockTransport([response(1, { guide: "hi" })]);
  const client = new Client(transport);

  const out = await client.usageGuide();
  assert.equal(out.guide, "hi");

  const request = JSON.parse(transport.requests[0]);
  assert.equal(request.jsonrpc, "2.0");
  assert.equal(request.method, "rigorix.usageGuide");
  assert.equal(request.id, 1);
  assert.deepEqual(request.params, {});
});

test("notification framing has no id", async () => {
  const transport = new MockTransport([""]);
  const client = new Client(transport);

  await client.notify("rigorix.audit.read", { execution_id: "e" });
  const request = JSON.parse(transport.requests[0]);
  assert.equal(request.id, undefined, "notification must omit `id`");
  assert.equal(request.method, "rigorix.audit.read");
});

test("batch framing is one JSON array", async () => {
  const transport = new MockTransport([
    JSON.stringify([
      { jsonrpc: "2.0", id: 1, result: { guide: "a" } },
      { jsonrpc: "2.0", id: 2, result: { guide: "b" } },
    ]),
  ]);
  const client = new Client(transport);

  const responses = await client.batchRaw([
    new BatchCall("rigorix.usageGuide", {}),
    new BatchCall("rigorix.usageGuide", {}),
  ]);
  assert.equal(responses.length, 2);

  const request = JSON.parse(transport.requests[0]);
  assert.ok(Array.isArray(request), "a batch is one JSON array");
  assert.equal(request.length, 2);
});

test("rpc error maps to the typed taxonomy", async () => {
  const transport = new MockTransport([
    JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      error: {
        code: -32010,
        message: "denied",
        data: { type: "denied_by_sequence", rule_id: "r1", step: "deploy" },
      },
    }),
  ]);
  const client = new Client(transport);

  await assert.rejects(
    () => client.run({ template_name: "t" }),
    (error: unknown) =>
      error instanceof JsonRpcError && error.apiError.kind === "denied_by_sequence",
  );
});

test("version negotiation accepts matching major", async () => {
  const transport = new MockTransport([
    response(1, {
      name: "rigorix-server",
      engine_version: "1.7.0",
      api_version: "1.0.0",
      schemas: ["api/catalog.json"],
      capabilities: ["jsonrpc-2.0"],
    }),
  ]);
  const client = new Client(transport);
  const version = await client.version();
  assert.equal(version.api_version, "1.0.0");
});

test("version negotiation rejects wrong major", async () => {
  const transport = new MockTransport([
    response(1, {
      name: "server",
      engine_version: "x",
      api_version: "2.0.0",
      schemas: [],
      capabilities: [],
    }),
  ]);
  const client = new Client(transport);
  await assert.rejects(() => client.version(), VersionMismatchError);
});

test("protocol error when neither result nor error", async () => {
  const transport = new MockTransport([JSON.stringify({ jsonrpc: "2.0", id: 1 })]);
  const client = new Client(transport);
  await assert.rejects(() => client.usageGuide(), ProtocolError);
});
