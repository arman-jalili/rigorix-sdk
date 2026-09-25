/** ADR-016 anchor-signed artifacts — Ed25519 verification (spec-only).
 *
 * Canonical signing form: Ed25519 over the compact JSON of the artifact with
 * `sig` set to `null`. The envelope's `prev_hash`/`envelope_hash` use the HMAC
 * canonical bytes instead; only the anchor artifacts use Ed25519.
 */

import { createPublicKey, verify } from "node:crypto";

import { stringify } from "lossless-json";

import { AnchorSignature } from "./errors.js";

type Json = any;

const LEDGER_RECEIPT = ["ledger_id", "envelope_hash", "sequence", "recorded_at", "sig"];
const HISTORY_SLICE = ["scope", "since", "actions", "head_hash", "sig"];
const COMPACTION_CHECKPOINT = [
  "sequence_from",
  "sequence_to",
  "reason",
  "prior_head",
  "new_head",
  "sig",
];
const HISTORY_ACTION = ["node", "principal", "at", "effect_key"];

/** Ed25519 SubjectPublicKeyInfo DER prefix (RFC 8410) before the 32-byte key. */
const ED25519_SPKI_PREFIX = Buffer.from("302a300506032b6570032100", "hex");

function signingBytes(artifact: Record<string, Json>, order: string[]): Buffer {
  const out: Record<string, Json> = {};
  for (const field of order) {
    if (!(field in artifact)) continue;
    const value = artifact[field];
    if (field === "sig") {
      out[field] = null;
    } else if (field === "actions" && Array.isArray(value)) {
      out[field] = value.map((action: Record<string, Json>) => {
        const item: Record<string, Json> = {};
        for (const key of HISTORY_ACTION) {
          if (key in action && !(key === "effect_key" && action[key] === null)) {
            item[key] = action[key];
          }
        }
        return item;
      });
    } else {
      out[field] = value;
    }
  }
  return Buffer.from(stringify(out) ?? "", "utf8");
}

function verifyEd25519(message: Buffer, signatureHex: string, publicKeyHex: string): void {
  const publicKey = createPublicKey({
    key: Buffer.concat([ED25519_SPKI_PREFIX, Buffer.from(publicKeyHex, "hex")]),
    format: "der",
    type: "spki",
  });
  if (!verify(null, message, publicKey, Buffer.from(signatureHex, "hex"))) {
    throw new AnchorSignature("invalid Ed25519 anchor signature");
  }
}

function verifyArtifact(artifact: Record<string, Json>, order: string[], publicKeyHex: string): void {
  const signature = artifact.sig;
  if (typeof signature !== "string" || signature.length === 0) {
    throw new AnchorSignature("artifact has no `sig`");
  }
  verifyEd25519(signingBytes(artifact, order), signature, publicKeyHex);
}

export function verifyLedgerReceipt(receipt: Record<string, Json>, publicKeyHex: string): void {
  verifyArtifact(receipt, LEDGER_RECEIPT, publicKeyHex);
}

export function verifyHistorySlice(slice: Record<string, Json>, publicKeyHex: string): void {
  verifyArtifact(slice, HISTORY_SLICE, publicKeyHex);
}

export function verifyCompactionCheckpoint(
  checkpoint: Record<string, Json>,
  publicKeyHex: string,
): void {
  verifyArtifact(checkpoint, COMPACTION_CHECKPOINT, publicKeyHex);
}
