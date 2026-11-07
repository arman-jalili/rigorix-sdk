/** Canonical envelope bytes — the pure half, with no Node imports.
 *
 * Both entries (Node and browser) must produce byte-identical JSON:
 * `serde_json::to_string(envelope with signature=None)` with struct field
 * order, `skip_serializing_if` fields omitted, non-skipped `Option` fields as
 * `null`, map fields (`scoring_results` / `dimensions`) sorted, and
 * `serde_json::Value` payload keys sorted.
 *
 * Field order comes from `schemas/envelope.json`; the caller supplies an
 * `OrderResolver` backed by its own corpus (fs in Node, the bundled map in the
 * browser). `lossless-json` preserves number lexemes (`1.0` stays `1.0`).
 */

import { LosslessNumber, parse, stringify } from "lossless-json";

type Json = unknown;

/** Resolve the declared field order for the root or a `$defs` struct. */
export type OrderResolver = (defName: string | null) => string[];

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

function canonicalizeNested(
  field: string,
  value: Json,
  defName: string,
  order: OrderResolver,
): Json {
  if (field === "scoring_results" && isRecord(value)) {
    const out: Record<string, Json> = {};
    for (const key of Object.keys(value).sort()) {
      const entry = canonicalizeObject(
        value[key] as Record<string, Json>,
        order("scoringResultRef"),
        order,
      );
      const dimensions = (entry as Record<string, Json>).dimensions;
      if (isRecord(dimensions)) {
        const sorted: Record<string, Json> = {};
        for (const name of Object.keys(dimensions).sort()) {
          sorted[name] = canonicalizeObject(
            dimensions[name] as Record<string, Json>,
            order("scoreDimensionRef"),
            order,
          );
        }
        (entry as Record<string, Json>).dimensions = sorted;
      }
      out[key] = entry;
    }
    return out;
  }
  if (Array.isArray(value)) {
    return value.map((item) =>
      canonicalizeObject(item as Record<string, Json>, order(defName), order),
    );
  }
  return canonicalizeObject(value as Record<string, Json>, order(defName), order);
}

function canonicalizeObject(
  obj: Record<string, Json>,
  fields: string[],
  order: OrderResolver,
): Record<string, Json> {
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
    else if (field in NESTED)
      out[field] = canonicalizeNested(field, value, NESTED[field], order);
    else out[field] = value;
  }
  return out;
}

/** The canonical JSON string (signature nulled), byte-identical in both entries. */
export function canonicalJson(
  envelope: string | Record<string, Json>,
  order: OrderResolver,
): string {
  const obj = (typeof envelope === "string" ? parse(envelope) : envelope) as Record<string, Json>;
  const ordered = canonicalizeObject(obj, order(null), order);
  return stringify(ordered) ?? "";
}
