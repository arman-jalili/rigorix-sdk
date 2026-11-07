/** Envelope HMAC verification + JSON Schema conformance (browser entry).
 *
 * Same rules as the Node entry, but HMAC-SHA256 goes through WebCrypto and the
 * signature comparison is over raw bytes (constant-time).
 */

import * as addFormatsModule from "ajv-formats";
import { parse } from "lossless-json";

import { SignatureMismatch, UnsignedNotDegraded } from "../errors.js";
import { createSchemaValidator, type AddFormats } from "../schema-core.js";
import { canonicalBytes } from "./canonical.js";
import { schemaFiles, schemaText } from "./corpus.js";
import { fromHex, hmacSha256, timingSafeEqual, toHex } from "./webcrypto.js";

type Json = any;

// Static ESM import (a browser has no `createRequire`); CJS interop puts the
// callable on `default` under Node/esbuild.
const addFormats = ((addFormatsModule as unknown as { default?: AddFormats }).default ??
  (addFormatsModule as unknown as AddFormats)) as AddFormats;

const { validateSchema, validateEnvelope } = createSchemaValidator(
  { schemaText, schemaFiles },
  addFormats,
);

export { validateSchema, validateEnvelope };

export async function verifySignature(
  envelope: string | Record<string, Json>,
  key: string,
): Promise<void> {
  const obj = (typeof envelope === "string" ? parse(envelope) : envelope) as Record<string, Json>;
  const signature = obj.signature;
  if (signature === null || signature === undefined) {
    if (obj.evidence_degraded === true) return;
    throw new UnsignedNotDegraded(
      "unsigned envelope without evidence_degraded=true (GAP-M-12 violation)",
    );
  }
  const expected = await hmacSha256(key, canonicalBytes(obj));
  let actual: Uint8Array;
  try {
    actual = fromHex(String(signature));
  } catch {
    throw new SignatureMismatch(
      `signature mismatch: expected ${toHex(expected)}, got ${signature}`,
    );
  }
  if (!timingSafeEqual(expected, actual)) {
    throw new SignatureMismatch(
      `signature mismatch: expected ${toHex(expected)}, got ${signature}`,
    );
  }
}
