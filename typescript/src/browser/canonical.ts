/** Canonical envelope bytes — browser entry (Uint8Array + WebCrypto SHA-256).
 *
 * The JSON rules live in `../canonical-core.ts`; the field order comes from the
 * bundled schema corpus. Byte-identical with the Node entry.
 */

import { canonicalJson } from "../canonical-core.js";
import { schemaText } from "./corpus.js";
import { sha256Hex } from "./webcrypto.js";

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

export function canonicalBytes(envelope: string | Record<string, Json>): Uint8Array {
  return new TextEncoder().encode(canonicalJson(envelope, order));
}

export async function envelopeHash(envelope: string | Record<string, Json>): Promise<string> {
  return sha256Hex(canonicalBytes(envelope));
}
