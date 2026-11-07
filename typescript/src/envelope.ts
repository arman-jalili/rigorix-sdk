/** Envelope HMAC verification + JSON Schema conformance (Node entry). */

import { createHmac, timingSafeEqual } from "node:crypto";
import { createRequire } from "node:module";

import { parse } from "lossless-json";

import { canonicalBytes } from "./canonical.js";
import { schemaFiles, schemaText } from "./corpus.js";
import { SignatureMismatch, UnsignedNotDegraded } from "./errors.js";
import { createSchemaValidator, type AddFormats } from "./schema-core.js";

type Json = any;

// `ajv-formats` is CJS; require it directly so the plugin function is callable
// under an ESM package (`tsc` mis-types its CJS default export as a namespace).
const addFormats = createRequire(import.meta.url)("ajv-formats") as AddFormats;

const { validateSchema, validateEnvelope } = createSchemaValidator(
  { schemaText, schemaFiles },
  addFormats,
);

export { validateSchema, validateEnvelope };

export function verifySignature(envelope: string | Record<string, Json>, key: string): void {
  const obj = (typeof envelope === "string" ? parse(envelope) : envelope) as Record<string, Json>;
  const signature = obj.signature;
  if (signature === null || signature === undefined) {
    if (obj.evidence_degraded === true) return;
    throw new UnsignedNotDegraded(
      "unsigned envelope without evidence_degraded=true (GAP-M-12 violation)",
    );
  }
  const expected = createHmac("sha256", key).update(canonicalBytes(obj)).digest("hex");
  const expectedBuffer = Buffer.from(expected, "utf8");
  const actualBuffer = Buffer.from(String(signature), "utf8");
  if (
    expectedBuffer.length !== actualBuffer.length ||
    !timingSafeEqual(expectedBuffer, actualBuffer)
  ) {
    throw new SignatureMismatch(`signature mismatch: expected ${expected}, got ${signature}`);
  }
}
