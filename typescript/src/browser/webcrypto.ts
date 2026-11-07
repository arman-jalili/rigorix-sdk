/** WebCrypto primitives for the browser entry.
 *
 * HMAC-SHA256, SHA-256, and Ed25519 go through the platform's own
 * `crypto.subtle`; no polyfill and no Node import. Signature comparisons are
 * over raw bytes and are constant-time.
 */

import { AnchorSignature } from "../errors.js";

function subtle(): SubtleCrypto {
  const crypto = globalThis.crypto;
  if (!crypto || !crypto.subtle) {
    throw new Error("WebCrypto is not available in this context");
  }
  return crypto.subtle;
}

/** TS 5.6 types `Uint8Array` as `ArrayBufferLike`; WebCrypto wants `BufferSource`. */
function bufferSource(bytes: Uint8Array): BufferSource {
  return bytes as unknown as BufferSource;
}

export function toHex(bytes: Uint8Array): string {
  let out = "";
  for (const byte of bytes) out += byte.toString(16).padStart(2, "0");
  return out;
}

export function fromHex(hex: string): Uint8Array {
  if (hex.length % 2 !== 0 || !/^[0-9a-fA-F]*$/.test(hex)) {
    throw new Error("invalid hex");
  }
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i += 1) {
    out[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

/** Constant-time comparison of two byte arrays (length first). */
export function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a[i] ^ b[i];
  return diff === 0;
}

export async function hmacSha256(key: string, message: Uint8Array): Promise<Uint8Array> {
  const cryptoKey = await subtle().importKey(
    "raw",
    bufferSource(new TextEncoder().encode(key)),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await subtle().sign("HMAC", cryptoKey, bufferSource(message)));
}

export async function sha256Hex(message: Uint8Array): Promise<string> {
  return toHex(new Uint8Array(await subtle().digest("SHA-256", bufferSource(message))));
}

/** Ed25519 SubjectPublicKeyInfo DER prefix (RFC 8410) before the 32-byte key. */
const ED25519_SPKI_PREFIX = fromHex("302a300506032b6570032100");

/**
 * Verify an Ed25519 signature with WebCrypto.
 *
 * Throws `AnchorSignature` when the platform does not expose Ed25519 or the
 * signature is invalid — the caller sees a typed failure, never a silent pass.
 */
export async function verifyEd25519(
  message: Uint8Array,
  signatureHex: string,
  publicKeyHex: string,
): Promise<void> {
  try {
    const publicKeyBytes = fromHex(publicKeyHex);
    if (publicKeyBytes.length !== 32) throw new Error("public key must be 32 bytes");
    const spki = new Uint8Array(ED25519_SPKI_PREFIX.length + publicKeyBytes.length);
    spki.set(ED25519_SPKI_PREFIX);
    spki.set(publicKeyBytes, ED25519_SPKI_PREFIX.length);
    const key = await subtle().importKey(
      "spki",
      bufferSource(spki),
      { name: "Ed25519" },
      false,
      ["verify"],
    );
    const signature = fromHex(signatureHex);
    if (signature.length !== 64) throw new Error("signature must be 64 bytes");
    if (
      !(await subtle().verify(
        { name: "Ed25519" },
        key,
        bufferSource(signature),
        bufferSource(message),
      ))
    ) {
      throw new AnchorSignature("invalid Ed25519 anchor signature");
    }
  } catch (error) {
    if (error instanceof AnchorSignature) throw error;
    throw new AnchorSignature(error instanceof Error ? error.message : String(error));
  }
}
