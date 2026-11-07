/** ADR-016 anchor-signed artifacts — Ed25519 via WebCrypto (browser entry).
 *
 * Canonical signing form: Ed25519 over the compact JSON of the artifact with
 * `sig` set to `null`. The envelope's `prev_hash`/`envelope_hash` use the HMAC
 * canonical bytes instead; only the anchor artifacts use Ed25519.
 */

import { stringify } from "lossless-json";

import { AnchorSignature } from "../errors.js";
import { verifyEd25519 } from "./webcrypto.js";

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

function signingBytes(artifact: Record<string, Json>, order: string[]): Uint8Array {
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
  return new TextEncoder().encode(stringify(out) ?? "");
}

async function verifyArtifact(
  artifact: Record<string, Json>,
  order: string[],
  publicKeyHex: string,
): Promise<void> {
  const signature = artifact.sig;
  if (typeof signature !== "string" || signature.length === 0) {
    throw new AnchorSignature("artifact has no `sig`");
  }
  await verifyEd25519(signingBytes(artifact, order), signature, publicKeyHex);
}

export async function verifyLedgerReceipt(
  receipt: Record<string, Json>,
  publicKeyHex: string,
): Promise<void> {
  await verifyArtifact(receipt, LEDGER_RECEIPT, publicKeyHex);
}

export async function verifyHistorySlice(
  slice: Record<string, Json>,
  publicKeyHex: string,
): Promise<void> {
  await verifyArtifact(slice, HISTORY_SLICE, publicKeyHex);
}

export async function verifyCompactionCheckpoint(
  checkpoint: Record<string, Json>,
  publicKeyHex: string,
): Promise<void> {
  await verifyArtifact(checkpoint, COMPACTION_CHECKPOINT, publicKeyHex);
}
