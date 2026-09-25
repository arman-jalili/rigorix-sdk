/** Envelope HMAC verification + JSON Schema conformance. */

import { createHmac, timingSafeEqual } from "node:crypto";

import { createRequire } from "node:module";

import { Ajv2020 } from "ajv/dist/2020.js";
import { parse } from "lossless-json";

import { canonicalBytes } from "./canonical.js";
import { schemaFiles, schemaText } from "./corpus.js";
import {
  SchemaViolation,
  SignatureMismatch,
  UnsignedNotDegraded,
  VerifyError,
} from "./errors.js";

type Json = any;

// `ajv-formats` is CJS; require it directly so the plugin function is callable
// under an ESM package (`tsc` mis-types its CJS default export as a namespace).
const addFormats = createRequire(import.meta.url)("ajv-formats") as (
  ajv: Ajv2020,
) => unknown;

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

let ajvInstance: Ajv2020 | undefined;

function ajv(): Ajv2020 {
  if (!ajvInstance) {
    const instance = new Ajv2020({ strict: false, allErrors: true });
    addFormats(instance);
    for (const rel of schemaFiles()) {
      let doc: Json;
      try {
        doc = JSON.parse(schemaText(rel));
      } catch {
        continue;
      }
      if (doc && typeof doc.$id === "string") {
        try {
          instance.addSchema(doc);
        } catch {
          // duplicate `$id` — first wins
        }
      }
    }
    ajvInstance = instance;
  }
  return ajvInstance;
}

export function validateSchema(schemaRel: string, instance: string | Json): void {
  const schema = JSON.parse(schemaText(schemaRel));
  const validator =
    typeof schema.$id === "string" ? ajv().getSchema(schema.$id) : ajv().compile(schema);
  if (!validator) throw new VerifyError(`schema ${schemaRel} is not registered`);
  const value = typeof instance === "string" ? JSON.parse(instance) : instance;
  if (!validator(value)) {
    throw new SchemaViolation(ajv().errorsText(validator.errors ?? undefined));
  }
}

export function validateEnvelope(instance: string | Json): void {
  validateSchema("envelope.json", instance);
}
