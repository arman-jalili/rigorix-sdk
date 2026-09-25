import { strict as assert } from "node:assert";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { parse } from "lossless-json";

import { envelopeHash } from "../src/canonical.js";
import { schemaText, schemasRoot } from "../src/corpus.js";
import { SchemaViolation, SignatureMismatch, UnsignedNotDegraded } from "../src/errors.js";
import { validateEnvelope, verifySignature } from "../src/envelope.js";

const KEY = "fixture-hmac-key-2026";

function envelopePaths(): string[] {
  const dir = join(schemasRoot(), "fixtures", "envelope");
  return readdirSync(dir)
    .filter((name) => name.endsWith(".json"))
    .sort()
    .map((name) => join(dir, name));
}

test("signed engine fixtures verify byte-exact", () => {
  let signed = 0;
  for (const path of envelopePaths()) {
    const text = readFileSync(path, "utf8");
    const lossless = parse(text) as Record<string, unknown>;
    if (lossless.signature === null || lossless.signature === undefined) continue;
    verifySignature(text, KEY); // byte-exact canonical form
    validateEnvelope(JSON.parse(text)); // schema conformance (plain JSON numbers)
    signed += 1;
  }
  assert.ok(signed >= 3, `expected >= 3 signed fixtures, found ${signed}`);
});

test("tampering is detected", () => {
  const path = envelopePaths().find(
    (candidate) => (parse(readFileSync(candidate, "utf8")) as any).signature !== null,
  );
  assert.ok(path);
  const data = JSON.parse(readFileSync(path!, "utf8"));
  data.total_tokens = Number(data.total_tokens ?? 0) + 1;
  assert.throws(() => verifySignature(data, KEY), SignatureMismatch);
});

test("unsigned must be degraded", () => {
  const path = envelopePaths().find(
    (candidate) => (parse(readFileSync(candidate, "utf8")) as any).signature === null,
  );
  assert.ok(path);
  const data = JSON.parse(readFileSync(path!, "utf8"));
  data.evidence_degraded = false;
  assert.throws(() => verifySignature(data, KEY), UnsignedNotDegraded);
});

test("schema rejects the wrong status case", () => {
  const path = envelopePaths().find((candidate) => candidate.includes("minimal"));
  assert.ok(path);
  const data = JSON.parse(readFileSync(path!, "utf8"));
  data.events[0].status = "success"; // engine emits "Success"
  assert.throws(() => validateEnvelope(data), SchemaViolation);
});

test("envelope hash is stable across string and object forms", () => {
  const path = envelopePaths().find((candidate) => candidate.includes("minimal"));
  assert.ok(path);
  const text = readFileSync(path!, "utf8");
  const fromText = envelopeHash(text);
  const fromObject = envelopeHash(parse(text) as Record<string, unknown>);
  assert.equal(fromText, fromObject);
  assert.equal(fromText.length, 64);
});

test("corpus exposes the canonical schema text", () => {
  assert.match(schemaText("envelope.json"), /Rigorix Audit Envelope/);
});
