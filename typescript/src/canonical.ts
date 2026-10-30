/** Canonical envelope bytes — byte-exact with the Rust engine + verifier.
 *
 * `serde_json::to_string(envelope with signature=None)` with struct field
 * order, `skip_serializing_if` fields omitted, non-skipped `Option` fields as
 * `null`, map fields (`scoring_results` / `dimensions`) sorted, and
 * `serde_json::Value` payload keys sorted. Field order is read from
 * `schemas/envelope.json` (its `properties` order mirrors the struct).
 *
 * `lossless-json` preserves number lexemes (`1.0` stays `1.0`) — JS
 * `JSON.stringify` would emit `1` and break the HMAC.
 */

import { createHash } from "node:crypto";
import { LosslessNumber, parse, stringify } from "lossless-json";

import { schemaText } from "./corpus.js";

type Json = unknown;

const SKIP_NONE = new Set([
  "identity",
  "effect_key",
  "producer_id",
  "sequence",
  "prev_hash",
  "history_integrity",
  "history_policy",
  "anchor_head",
  "decision_context_ref",
  "scope_check",
  "payload",
  "check_digest",
  "authority_digest",
  "check_writable",
  "attribution",
]);

const SKIP_EMPTY = new Set([
  "file_paths",
  "scoring_results",
  "approval_events",
  "scope_violations",
  "sequence_policy_findings",
  "requirement_findings",
  "precondition_findings",
]);

const NESTED: Record<string, string> = {
  identity: "identityRef",
  events: "executionEventRef",
  approval_events: "approvalRecordRef",
  scope_violations: "scopeViolationRef",
  sequence_policy_findings: "sequencePolicyFindingRef",
  requirement_findings: "requirementFindingRef",
  precondition_findings: "preconditionFindingRef",
  scoring_results: "scoringResultRef",
};

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

function isLossless(value: Json): boolean {
  return value instanceof LosslessNumber;
}

function isRecord(value: Json): value is Record<string, Json> {
  return typeof value === "object" && value !== null && !Array.isArray(value) && !isLossless(value);
}

function sortValue(value: Json): Json {
  if (!isRecord(value)) {
    if (Array.isArray(value)) return value.map(sortValue);
    return value;
  }
  const out: Record<string, Json> = {};
  for (const key of Object.keys(value).sort()) out[key] = sortValue(value[key]);
  return out;
}

function canonicalizeNested(field: string, value: Json, defName: string): Json {
  if (field === "scoring_results" && isRecord(value)) {
    const out: Record<string, Json> = {};
    for (const key of Object.keys(value).sort()) {
      const entry = canonicalizeObject(value[key] as Record<string, Json>, order("scoringResultRef"));
      const dimensions = (entry as Record<string, Json>).dimensions;
      if (isRecord(dimensions)) {
        const sorted: Record<string, Json> = {};
        for (const name of Object.keys(dimensions).sort()) {
          sorted[name] = canonicalizeObject(dimensions[name] as Record<string, Json>, order("scoreDimensionRef"));
        }
        (entry as Record<string, Json>).dimensions = sorted;
      }
      out[key] = entry;
    }
    return out;
  }
  if (Array.isArray(value)) {
    return value.map((item) => canonicalizeObject(item as Record<string, Json>, order(defName)));
  }
  return canonicalizeObject(value as Record<string, Json>, order(defName));
}

function canonicalizeObject(obj: Record<string, Json>, fields: string[]): Record<string, Json> {
  const out: Record<string, Json> = {};
  for (const field of fields) {
    if (!(field in obj)) continue;
    const value = obj[field];
    if (value === null && SKIP_NONE.has(field)) continue;
    if (
      (Array.isArray(value) || isRecord(value)) &&
      (Array.isArray(value) ? value.length : Object.keys(value as object).length) === 0 &&
      SKIP_EMPTY.has(field)
    ) {
      continue;
    }
    if (field === "signature") out[field] = null;
    else if (field === "payload") out[field] = sortValue(value);
    else if (field in NESTED) out[field] = canonicalizeNested(field, value, NESTED[field]);
    else out[field] = value;
  }
  return out;
}

export function canonicalBytes(envelope: string | Record<string, Json>): Buffer {
  const obj = (typeof envelope === "string" ? parse(envelope) : envelope) as Record<string, Json>;
  const ordered = canonicalizeObject(obj, order(null));
  return Buffer.from(stringify(ordered) ?? "", "utf8");
}

export function envelopeHash(envelope: string | Record<string, Json>): string {
  return createHash("sha256").update(canonicalBytes(envelope)).digest("hex");
}
