import { strict as assert } from "node:assert";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { schemasRoot } from "../src/corpus.js";

/** A byte snapshot of every file under `root`, keyed by relative path. */
function snapshot(root: string): Record<string, string> {
  const out: Record<string, string> = {};
  const walk = (dir: string): void => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else out[relative(root, full).split("\\").join("/")] = readFileSync(full).toString("base64");
    }
  };
  walk(root);
  return out;
}

test("materialised corpus matches the canonical schemas/", () => {
  if (process.env.RIGORIX_SDK_SCHEMAS) return; // explicit override: nothing to compare
  // dist/test -> dist -> typescript -> repo root
  const canonical = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "schemas");
  assert.deepEqual(snapshot(schemasRoot()), snapshot(canonical));
});
