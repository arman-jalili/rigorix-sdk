/** Browser corpus — schemas are bundled as string constants at build time.
 *
 * `scripts/bundle-schemas.mjs` writes `corpus.generated.ts` from the canonical
 * `schemas/` tree (fixtures excluded). Nothing here imports a Node built-in.
 */

import { SCHEMAS } from "./corpus.generated.js";

export function schemaText(relPath: string): string {
  const text = SCHEMAS[relPath];
  if (text === undefined) throw new Error(`contract schema not bundled: ${relPath}`);
  return text;
}

export function schemaFiles(): string[] {
  return Object.keys(SCHEMAS).sort();
}
