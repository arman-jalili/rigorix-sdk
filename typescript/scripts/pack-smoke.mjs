/**
 * Pack-time smoke test (SDK-C6-PACKAGING): run from a clean project with the
 * packed `rigorix-verifier` installed and `RIGORIX_SDK_SCHEMAS` unset. Proves
 * the tarball carries a REAL corpus. Copy this file next to the temp project's
 * `node_modules/` (so the bare import resolves) and run it with `node`.
 */
import { fixtureText, schemasRoot, verifyChain, verifySignature } from "rigorix-verifier";

verifySignature(fixtureText("envelope/envelope-anchored-signed.json"), "fixture-hmac-key-2026");
verifyChain(JSON.parse(fixtureText("integrity/chain.json")));
console.log("packed typescript verifier smoke OK:", schemasRoot());
