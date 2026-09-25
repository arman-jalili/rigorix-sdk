/** Contract-corpus resolution (SDK-C6 / #21).
 *
 * Order (mirrors the Rust `rigorix-verifier`):
 * 1. `RIGORIX_SDK_SCHEMAS` — an explicit external corpus (CI/local override).
 * 2. The bundled `_schemas` directory (a symlink to the repo-root `schemas/`
 *    in-tree; dereferenced when the package is packed).
 */

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
// dist/src -> package root (typescript/)
const packageRoot = join(here, "..", "..");

export function schemasRoot(): string {
  const override = process.env.RIGORIX_SDK_SCHEMAS;
  if (override && override.length > 0) return override;
  const bundled = join(packageRoot, "_schemas");
  if (existsSync(bundled)) return bundled;
  throw new Error(
    "contract corpus not found: set RIGORIX_SDK_SCHEMAS or bundle typescript/_schemas",
  );
}

export function schemaText(relPath: string): string {
  return readFileSync(join(schemasRoot(), relPath), "utf8");
}

export function fixtureText(relPath: string): string {
  return readFileSync(join(schemasRoot(), "fixtures", relPath), "utf8");
}

export function schemaFiles(): string[] {
  const root = schemasRoot();
  const out: string[] = [];
  const walk = (dir: string): void => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith(".json")) {
        out.push(relative(root, full).split("\\").join("/"));
      }
    }
  };
  walk(root);
  return out.sort();
}
