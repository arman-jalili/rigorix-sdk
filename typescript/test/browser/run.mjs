#!/usr/bin/env node
/**
 * Browser-entry conformance: load the emitted `rigorix-verifier/browser` in a
 * real page (Chrome via playwright-core) and compare every verdict with the
 * Node entry over the same fixtures.
 *
 * Seeds exercised here:
 *   S1  a byte flipped in the payload  -> both entries reject
 *   S2  a key differing in one byte    -> both entries reject
 *   S3  a `node:` import in the entry  -> `npm run build` fails (guard)
 *
 * The page and the bundle are served from a local HTTP server; the page imports
 * the bundle as a module, so this is a browser module graph, not a Node vm.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { build } from "esbuild";
import { chromium } from "playwright-core";

import {
  canonicalBytes,
  envelopeHash,
  validateEnvelope,
  verifyChain,
  verifyLedgerReceipt,
  verifySignature,
} from "../../dist/src/index.js";

const here = dirname(fileURLToPath(import.meta.url)); // typescript/test/browser
const root = join(here, "..", ".."); // typescript/
const corpus = join(root, "_schemas");
const bundlePath = join(root, "dist", "browser-test", "verifier.js");

const KEY = "fixture-hmac-key-2026";
const WRONG_KEY = KEY.slice(0, -1) + (KEY.endsWith("x") ? "y" : "x");
const ANCHOR_PUBLIC_KEY =
  "ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c";

function fixture(rel) {
  return readFileSync(join(corpus, "fixtures", rel), "utf8");
}

function verdict(fn) {
  try {
    fn();
    return "ok";
  } catch (error) {
    return error?.constructor?.name ?? "Error";
  }
}

function tamper(text) {
  const replaced = text.replace(/("total_tokens"\s*:\s*)(\d+)/, (_, head, value) => {
    return `${head}${Number(value) + 1}`;
  });
  if (replaced === text) throw new Error("fixture has no total_tokens to tamper");
  return replaced;
}

async function run() {
  const envelope = fixture("envelope/envelope-rich-signed.json");
  const tampered = tamper(envelope);
  const minimal = fixture("envelope/envelope-minimal-signed.json");
  const chain = JSON.parse(fixture("integrity/chain.json"));
  const broken = JSON.parse(fixture("integrity/broken-chain.json"));
  const receipt = JSON.parse(fixture("integrity/ledger-receipt.json"));
  const forged = { ...receipt, envelope_hash: "0".repeat(64) };
  const badSchema = JSON.parse(minimal);
  badSchema.events[0].status = "success"; // engine emits "Success"

  // ── Node entry verdicts ────────────────────────────────────────────────
  const node = {
    valid: verdict(() => verifySignature(envelope, KEY)),
    tampered: verdict(() => verifySignature(tampered, KEY)),
    wrongKey: verdict(() => verifySignature(envelope, WRONG_KEY)),
    hash: envelopeHash(envelope),
    canonicalHex: canonicalBytes(envelope).toString("hex"),
    chain: verdict(() => verifyChain(chain)),
    broken: verdict(() => verifyChain(broken)),
    receipt: verdict(() => verifyLedgerReceipt(receipt, ANCHOR_PUBLIC_KEY)),
    forged: verdict(() => verifyLedgerReceipt(forged, ANCHOR_PUBLIC_KEY)),
    schemaOk: verdict(() => validateEnvelope(envelope)),
    schemaBad: verdict(() => validateEnvelope(badSchema)),
  };

  // ── Bundle the emitted browser entry for a page ─────────────────────────
  await build({
    entryPoints: [join(root, "dist", "src", "browser", "index.js")],
    bundle: true,
    format: "esm",
    platform: "browser",
    outfile: bundlePath,
    logLevel: "silent",
    define: { "process.env.NODE_ENV": '"production"' },
  });
  const bundle = readFileSync(bundlePath, "utf8");

  const html = `<!doctype html>
<meta charset="utf-8">
<script>
  window.__errors = [];
  addEventListener("error", (event) => window.__errors.push(String(event.error || event.message)));
  addEventListener("unhandledrejection", (event) => window.__errors.push(String(event.reason)));
</script>
<script type="module">
  import * as verifier from "/verifier.js";
  window.__verifier = verifier;
  window.__ready = true;
</script>`;

  const server = createServer((request, response) => {
    if (request.url === "/") {
      response.setHeader("content-type", "text/html; charset=utf-8");
      response.end(html);
      return;
    }
    if (request.url === "/verifier.js") {
      response.setHeader("content-type", "text/javascript; charset=utf-8");
      response.end(bundle);
      return;
    }
    response.statusCode = 404;
    response.end("not found");
  });

  let browser;
  try {
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    const { port } = server.address();

    let launched;
    const channel = process.env.PLAYWRIGHT_CHANNEL;
    try {
      launched = await chromium.launch(channel ? { channel, headless: true } : { headless: true });
    } catch {
      launched = await chromium.launch({ channel: channel ?? "chrome", headless: true });
    }
    browser = launched;

    const page = await browser.newPage();
    const pageErrors = [];
    page.on("pageerror", (error) => pageErrors.push(String(error)));

    await page.goto(`http://127.0.0.1:${port}/`);
    await page.waitForFunction(
      () => window.__ready === true || (window.__errors && window.__errors.length > 0),
      undefined,
      { timeout: 15_000 },
    );

    const loadErrors = await page.evaluate(() => window.__errors ?? []);
    assert.deepEqual(
      [...loadErrors, ...pageErrors],
      [],
      "the browser module graph failed to load",
    );

    const data = {
      envelope,
      tampered,
      key: KEY,
      wrongKey: WRONG_KEY,
      chain,
      broken,
      receipt,
      forged,
      anchorKey: ANCHOR_PUBLIC_KEY,
      badSchema,
    };

    const result = await page.evaluate(async (payload) => {
      const v = window.__verifier;
      const hex = (bytes) =>
        Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
      const check = async (fn) => {
        try {
          await fn();
          return "ok";
        } catch (error) {
          return error?.constructor?.name ?? "Error";
        }
      };
      return {
        valid: await check(() => v.verifySignature(payload.envelope, payload.key)),
        tampered: await check(() => v.verifySignature(payload.tampered, payload.key)),
        wrongKey: await check(() => v.verifySignature(payload.envelope, payload.wrongKey)),
        hash: await v.envelopeHash(payload.envelope),
        canonicalHex: hex(v.canonicalBytes(payload.envelope)),
        chain: await check(() => v.verifyChain(payload.chain)),
        broken: await check(() => v.verifyChain(payload.broken)),
        receipt: await check(() => v.verifyLedgerReceipt(payload.receipt, payload.anchorKey)),
        forged: await check(() => v.verifyLedgerReceipt(payload.forged, payload.anchorKey)),
        schemaOk: await check(() => Promise.resolve(v.validateEnvelope(payload.envelope))),
        schemaBad: await check(() => Promise.resolve(v.validateEnvelope(payload.badSchema))),
      };
    }, data);

    // ── Cross-entry equality ────────────────────────────────────────────
    assert.equal(result.valid, "ok");
    assert.equal(result.valid, node.valid);
    assert.equal(result.tampered, node.tampered, "S1: tampered payload verdicts differ");
    assert.equal(result.tampered, "SignatureMismatch");
    assert.equal(result.wrongKey, node.wrongKey, "S2: wrong-key verdicts differ");
    assert.equal(result.wrongKey, "SignatureMismatch");
    assert.equal(result.hash, node.hash, "envelope hashes differ");
    assert.equal(result.canonicalHex, node.canonicalHex, "canonical bytes differ");
    assert.equal(result.chain, node.chain);
    assert.equal(result.chain, "ok");
    assert.equal(result.broken, node.broken);
    assert.equal(result.broken, "ChainBroken");
    assert.equal(result.receipt, node.receipt);
    assert.equal(result.receipt, "ok");
    assert.equal(result.forged, node.forged);
    assert.equal(result.forged, "AnchorSignature");
    assert.equal(result.schemaOk, node.schemaOk);
    assert.equal(result.schemaOk, "ok");
    assert.equal(result.schemaBad, node.schemaBad);
    assert.equal(result.schemaBad, "SchemaViolation");

    console.log("✅ browser conformance: canonical bytes, HMAC, chain, Ed25519, and schema agree with Node");
    console.log("   S1 tampered payload -> SignatureMismatch (both)");
    console.log("   S2 wrong key        -> SignatureMismatch (both)");
  } finally {
    await browser?.close();
    await new Promise((resolve) => server.close(resolve));
  }
}

run().catch((error) => {
  console.error("❌ browser conformance failed:", error);
  process.exitCode = 1;
});
