/** ADR-016 local per-producer chain verification. */

import { verifyCompactionCheckpoint } from "./anchor.js";
import { envelopeHash } from "./canonical.js";
import { ChainBroken } from "./errors.js";

type Json = any;

export function verifyChain(envelopes: Array<Record<string, Json>>): void {
  verifyChainWithCheckpoints(envelopes, [], "");
}

export function verifyChainWithCheckpoints(
  envelopes: Array<Record<string, Json>>,
  checkpoints: Array<Record<string, Json>>,
  anchorPublicKeyHex: string,
): void {
  for (const checkpoint of checkpoints) {
    verifyCompactionCheckpoint(checkpoint, anchorPublicKeyHex);
  }

  const producers = new Map<string, Array<Record<string, Json>>>();
  for (const envelope of envelopes) {
    const producer = envelope.producer_id;
    if (producer !== null && producer !== undefined && envelope.sequence !== null && envelope.sequence !== undefined) {
      const list = producers.get(producer) ?? [];
      list.push(envelope);
      producers.set(producer, list);
    }
  }

  for (const producer of [...producers.keys()].sort()) {
    const chain = (producers.get(producer) ?? []).slice().sort((a, b) => Number(a.sequence) - Number(b.sequence));
    const base = Number(chain[0].sequence);
    if (base !== 0) {
      throw new ChainBroken(
        `producer '${producer}': chain starts at sequence ${base}, not genesis 0`,
      );
    }
    if (chain[0].prev_hash !== null && chain[0].prev_hash !== undefined) {
      throw new ChainBroken(`producer '${producer}': genesis envelope carries a prev_hash`);
    }
    for (let i = 1; i < chain.length; i += 1) {
      const prev = chain[i - 1];
      const next = chain[i];
      const prevSequence = Number(prev.sequence);
      const nextSequence = Number(next.sequence);
      if (nextSequence <= prevSequence) {
        throw new ChainBroken(
          `producer '${producer}': sequence not strictly increasing (${prevSequence} -> ${nextSequence})`,
        );
      }
      const prevHash = envelopeHash(prev);
      if (nextSequence === prevSequence + 1) {
        if (next.prev_hash !== prevHash) {
          throw new ChainBroken(
            `producer '${producer}': prev_hash mismatch at sequence ${nextSequence}`,
          );
        }
        continue;
      }
      const link = next.prev_hash;
      if (link === null || link === undefined) {
        throw new ChainBroken(
          `producer '${producer}': missing prev_hash after gap at sequence ${nextSequence}`,
        );
      }
      const covered = checkpoints.some(
        (checkpoint) =>
          Number(checkpoint.sequence_from) === prevSequence + 1 &&
          Number(checkpoint.sequence_to) === nextSequence - 1 &&
          checkpoint.prior_head === prevHash &&
          checkpoint.new_head === link,
      );
      if (!covered) {
        throw new ChainBroken(
          `producer '${producer}': uncovered gap sequences ${prevSequence + 1}..=${nextSequence - 1}`,
        );
      }
    }
  }
}
