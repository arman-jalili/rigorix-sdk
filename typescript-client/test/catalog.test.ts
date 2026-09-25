import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import {
  API_ERROR_TYPES,
  ApiError,
  JsonRpcError,
} from "../src/error.js";
import { assertNoRawStepExecution, find, names } from "../src/catalog.js";

function schemasRoot(): string {
  const override = process.env.RIGORIX_SDK_SCHEMAS;
  if (override && override.length > 0) return override;
  return join(dirname(fileURLToPath(import.meta.url)), "..", "..", "_schemas");
}

function readSchema(rel: string): any {
  return JSON.parse(readFileSync(join(schemasRoot(), rel), "utf8"));
}

test("client binds every frozen catalog method", () => {
  const catalog = readSchema("api/catalog.json");
  const frozen: string[] = catalog.methods.map((method: any) => method.name).sort();
  const bound: string[] = [...names()].sort();
  assert.deepEqual(bound, frozen, "the client catalog must mirror catalog.json");
  for (const name of frozen) {
    assert.ok(find(name), `${name} must have an explicit binding`);
  }
  assert.doesNotThrow(() => assertNoRawStepExecution());
});

test("every error type maps to a distinct kind and round-trips", () => {
  const errors = readSchema("api/errors.json");
  const declared: string[] = errors.$defs.errorType.enum;
  const kinds = new Set<string>();
  for (const name of declared) {
    const error = new ApiError(name, "m");
    assert.equal(error.kind, name, `kind round-trip for ${name}`);
    kinds.add(error.kind);
  }
  assert.equal(kinds.size, declared.length, "a distinct kind per declared type");
  assert.deepEqual(API_ERROR_TYPES.slice().sort(), declared.slice().sort());

  const unknown = new ApiError("totally_unknown", "m");
  assert.equal(unknown.kind, "unknown");
  assert.equal(unknown.type, "totally_unknown");
});

test("JsonRpcError exposes the typed api error", () => {
  const error = new JsonRpcError({
    code: -32010,
    message: "denied",
    data: { type: "denied_by_sequence", rule_id: "r1", step: "deploy" },
  });
  assert.equal(error.apiError.kind, "denied_by_sequence");
  assert.equal(error.apiError.ruleId, "r1");
  assert.equal(error.apiError.step, "deploy");
});
