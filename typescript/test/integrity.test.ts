import { strict as assert } from "node:assert";
import { test } from "node:test";

import { parse } from "lossless-json";

import {
  verifyCompactionCheckpoint,
  verifyHistorySlice,
  verifyLedgerReceipt,
} from "../src/anchor.js";
import { verifyChain, verifyChainWithCheckpoints } from "../src/chain.js";
import { fixtureText } from "../src/corpus.js";
import { AnchorSignature, ChainBroken } from "../src/errors.js";

const ANCHOR_PUBLIC_KEY =
  "ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c";

function read(name: string): any {
  return parse(fixtureText(`integrity/${name}`));
}

test("valid chain verifies", () => {
  verifyChain(read("chain.json"));
});

test("broken chain is rejected", () => {
  assert.throws(() => verifyChain(read("broken-chain.json")), ChainBroken);
});

test("altered predecessor is rejected", () => {
  const chain = read("chain.json");
  chain[chain.length - 1].prev_hash = "0".repeat(64);
  assert.throws(() => verifyChain(chain), ChainBroken);
});

test("duplicate sequence is rejected", () => {
  const chain = read("chain.json");
  chain[chain.length - 1].sequence = chain[chain.length - 2].sequence;
  assert.throws(() => verifyChain(chain), ChainBroken);
});

test("checkpoint covers the gap", () => {
  const broken = read("broken-chain.json");
  const checkpoint = read("compaction-checkpoint.json");
  assert.throws(() => verifyChain(broken), ChainBroken);
  verifyChainWithCheckpoints(broken, [checkpoint], ANCHOR_PUBLIC_KEY);
});

test("forged checkpoint does not cover", () => {
  const broken = read("broken-chain.json");
  const forged = read("compaction-checkpoint.json");
  forged.new_head = "0".repeat(64);
  assert.throws(
    () => verifyChainWithCheckpoints(broken, [forged], ANCHOR_PUBLIC_KEY),
    AnchorSignature,
  );
});

test("history slice verifies", () => {
  verifyHistorySlice(read("history-slice.json"), ANCHOR_PUBLIC_KEY);
});

test("history slice tamper is rejected", () => {
  const forged = read("history-slice.json");
  forged.actions[0].node = "forged_node";
  assert.throws(() => verifyHistorySlice(forged, ANCHOR_PUBLIC_KEY), AnchorSignature);
});

test("ledger receipt verifies", () => {
  verifyLedgerReceipt(read("ledger-receipt.json"), ANCHOR_PUBLIC_KEY);
});

test("compaction checkpoint verifies", () => {
  verifyCompactionCheckpoint(read("compaction-checkpoint.json"), ANCHOR_PUBLIC_KEY);
});
