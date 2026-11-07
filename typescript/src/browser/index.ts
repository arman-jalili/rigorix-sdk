/** rigorix-verifier/browser — the same canonical bytes, verified with WebCrypto.
 *
 * No Node built-in imports. Async where the platform crypto is async:
 * `verifySignature`, `envelopeHash`, the chain verifiers, and the Ed25519 anchor
 * verifiers return promises. `canonicalBytes` returns `Uint8Array`; the Node
 * entry returns `Buffer`.
 */

export {
  verifyCompactionCheckpoint,
  verifyHistorySlice,
  verifyLedgerReceipt,
} from "./anchor.js";
export { canonicalBytes, envelopeHash } from "./canonical.js";
export { verifyChain, verifyChainWithCheckpoints } from "./chain.js";
export { schemaFiles, schemaText } from "./corpus.js";
export { validateEnvelope, validateSchema, verifySignature } from "./envelope.js";
export * from "../errors.js";
