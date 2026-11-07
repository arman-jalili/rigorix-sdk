/** JSON Schema conformance over a pluggable contract corpus.
 *
 * Shared by both entries: Node passes `corpus.ts` (fs) and `ajv-formats` loaded
 * through `createRequire`; the browser passes the bundled corpus and a static
 * `ajv-formats` import. Ajv itself is isomorphic.
 */

import { Ajv2020 } from "ajv/dist/2020.js";

import { SchemaViolation, VerifyError } from "./errors.js";

type Json = any;

/** The schema surface both entries must provide. */
export interface SchemaCorpus {
  schemaText(relPath: string): string;
  schemaFiles(): string[];
}

/** `ajv-formats` is CJS; each entry supplies the callable in its own way. */
export type AddFormats = (ajv: Ajv2020) => unknown;

export interface SchemaValidator {
  validateSchema(schemaRel: string, instance: string | Json): void;
  validateEnvelope(instance: string | Json): void;
}

export function createSchemaValidator(
  corpus: SchemaCorpus,
  addFormats: AddFormats,
): SchemaValidator {
  let ajvInstance: Ajv2020 | undefined;

  function ajv(): Ajv2020 {
    if (!ajvInstance) {
      const instance = new Ajv2020({ strict: false, allErrors: true });
      addFormats(instance);
      for (const rel of corpus.schemaFiles()) {
        let doc: Json;
        try {
          doc = JSON.parse(corpus.schemaText(rel));
        } catch {
          continue;
        }
        if (doc && typeof doc.$id === "string") {
          try {
            instance.addSchema(doc);
          } catch {
            // duplicate `$id` — first wins
          }
        }
      }
      ajvInstance = instance;
    }
    return ajvInstance;
  }

  function validateSchema(schemaRel: string, instance: string | Json): void {
    const schema = JSON.parse(corpus.schemaText(schemaRel));
    const validator =
      typeof schema.$id === "string" ? ajv().getSchema(schema.$id) : ajv().compile(schema);
    if (!validator) throw new VerifyError(`schema ${schemaRel} is not registered`);
    const value = typeof instance === "string" ? JSON.parse(instance) : instance;
    if (!validator(value)) {
      throw new SchemaViolation(ajv().errorsText(validator.errors ?? undefined));
    }
  }

  function validateEnvelope(instance: string | Json): void {
    validateSchema("envelope.json", instance);
  }

  return { validateSchema, validateEnvelope };
}
