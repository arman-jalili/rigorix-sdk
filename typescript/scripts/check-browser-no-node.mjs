#!/usr/bin/env node
/**
 * Fail the build if the emitted browser entry imports Node.
 *
 * A browser page cannot resolve `node:*`. The guard checks the *emitted*
 * `dist/src/browser/**`, not the source, so a re-export or a generated file is
 * covered too. Seed it by adding `import "node:fs"` to a browser file: the
 * build names the file and line.
 */
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "dist", "src", "browser");

if (!existsSync(root)) {
  console.log("browser guard: no dist/src/browser yet (skipped)");
  process.exit(0);
}

const hits = [];
const walk = (dir) => {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full);
      continue;
    }
    const text = readFileSync(full, "utf8");
    for (const [index, line] of text.split("\n").entries()) {
      if (line.includes("node:")) {
        hits.push(`${relative(process.cwd(), full)}:${index + 1}: ${line.trim()}`);
      }
    }
  }
};
walk(root);

if (hits.length > 0) {
  console.error("❌ browser entry imports node:");
  for (const hit of hits) console.error(`  ${hit}`);
  process.exit(1);
}
console.log("✅ browser entry has no node: imports");
