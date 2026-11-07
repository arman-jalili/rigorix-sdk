/** Canonical envelope bytes — Node entry (Buffer + node:crypto).
 *
 * The byte rules and field order live in `canonical-core.ts` so the browser
 * entry computes exactly the same JSON. This file only adds the Node return
 * type (`Buffer`) and the SHA-256 hash.
 */

import { createHash } from "node:crypto";

import { canonicalJson } from "./canonical-core.js";
import { schemaText } from "./corpus.js";

type Json = unknown;

const ORDERS = new Map<string, string[]>();

function order(defName: string | null): string[] {
  const key = defName ?? "__root__";
  const cached = ORDERS.get(key);
  if (cached) return cached;
  const schema = JSON.parse(schemaText("envelope.json")) as Record<string, any>;
  const fields =
    defName === null
      ? Object.keys(schema.properties)
      : Object.keys(schema.$defs[defName].properties);
  ORDERS.set(key, fields);
  return fields;
}

export function canonicalBytes(envelope: string | Record<string, Json>): Buffer {
  return Buffer.from(canonicalJson(envelope, order), "utf8");
}

export function envelopeHash(envelope: string | Record<string, Json>): string {
  return createHash("sha256").update(canonicalBytes(envelope)).digest("hex");
}
