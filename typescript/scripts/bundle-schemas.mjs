#!/usr/bin/env node
/**
 * Materialise the canonical contract corpus into `typescript/_schemas` as a
 * REAL directory, because npm does **not** dereference the repo-root `schemas/`
 * symlink into the packed artifact (verified: `npm pack` shipped 0 files).
 *
 * The source of truth stays `<repo>/schemas`; this copy is generated (and
 * gitignored). Run from npm `prepack`/`build` and the pack gate. Mirrors what
 * `cargo package` does for the Rust `rigorix-schemas` crate (SDK-C6-PACKAGING).
 */
import {
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  rmSync,
} from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url)); // typescript/scripts
const packageRoot = join(here, ".."); // typescript/
const repoRoot = join(packageRoot, ".."); // repo root
const source = join(repoRoot, "schemas");
const target = join(packageRoot, "_schemas");

if (!existsSync(source)) {
  console.error(`bundle-schemas: canonical corpus not found at ${source}`);
  process.exit(1);
}

// Replace a stale symlink or copy with a real directory.
rmSync(target, { recursive: true, force: true });
mkdirSync(target, { recursive: true });
cpSync(source, target, { recursive: true, dereference: true });

function count(dir) {
  return readdirSync(dir, { withFileTypes: true }).reduce(
    (total, entry) =>
      total + (entry.isDirectory() ? count(join(dir, entry.name)) : 1),
    0,
  );
}

console.log(
  `bundle-schemas: ${count(target)} files -> ${relative(packageRoot, target)}`,
);
