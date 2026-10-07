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

test("anchored engine fixture binds anchor_head at the engine position", () => {
  const path = join(schemasRoot(), "fixtures", "envelope", "envelope-anchored-signed.json");
  const text = readFileSync(path, "utf8");
  const data = JSON.parse(text) as any;
  assert.equal(data.history_integrity, "anchored");
  assert.equal(
    data.anchor_head,
    "3f2a9c1e7b4d5f6081a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708",
  );
  assert.ok(Array.isArray(data.approval_events) && data.approval_events.length > 0);

  // Byte-exact parity — the regression: the field is NOT dropped.
  verifySignature(text, KEY);
  validateEnvelope(data);

  // The field is signed; tampering with the head is detected.
  assert.throws(() => verifySignature({ ...data, anchor_head: "0".repeat(64) }, KEY), SignatureMismatch);

  // A local_unanchored fixture carries no anchor_head and still verifies.
  const localPath = envelopePaths().find((candidate) => candidate.includes("minimal"))!;
  const localText = readFileSync(localPath, "utf8");
  assert.ok(!localText.includes('"anchor_head"'));
  verifySignature(localText, KEY);
});

test("precondition findings fixture verifies (ADR-017)", () => {
  const path = join(schemasRoot(), "fixtures", "envelope", "envelope-precondition-signed.json");
  const text = readFileSync(path, "utf8");
  const data = JSON.parse(text) as any;
  const findings = data.precondition_findings;
  assert.deepEqual(
    findings.map((finding: any) => finding.outcome),
    ["failed", "passed", "error"],
  );
  assert.deepEqual(
    findings.map((finding: any) => finding.exit_code),
    [3, 0, null],
  );

  verifySignature(text, KEY);
  validateEnvelope(data);

  const tampered = JSON.parse(text);
  tampered.precondition_findings[0].inputs_hash = "0".repeat(64);
  assert.throws(() => verifySignature(tampered, KEY), SignatureMismatch);

  const minimalPath = envelopePaths().find((candidate) => candidate.includes("minimal"))!;
  const minimalText = readFileSync(minimalPath, "utf8");
  assert.ok(!minimalText.includes("precondition_findings"));
  verifySignature(minimalText, KEY);
});
