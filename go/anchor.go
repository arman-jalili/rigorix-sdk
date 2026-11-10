// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package rigorix

import (
	"crypto/ed25519"
	"encoding/hex"
	"fmt"
)

// Anchor-artifact field orders (mirror the frozen `api/*.json` `x-signing`).
var (
	ledgerReceiptOrder = []string{"ledger_id", "envelope_hash", "sequence", "recorded_at", "sig"}
	historySliceOrder  = []string{"scope", "since", "actions", "head_hash", "sig"}
	compactionOrder    = []string{"sequence_from", "sequence_to", "reason", "prior_head", "new_head", "sig"}
)

func verifyAnchor(artifact any, order []string, publicKeyHex string) error {
	obj, err := asObject(artifact)
	if err != nil {
		return err
	}
	signature, ok := obj["sig"].(string)
	if !ok || signature == "" {
		return fmt.Errorf("%w: artifact has no `sig`", ErrAnchorSignature)
	}
	publicKey, err := hex.DecodeString(publicKeyHex)
	if err != nil || len(publicKey) != ed25519.PublicKeySize {
		return fmt.Errorf("%w: invalid public key", ErrAnchorSignature)
	}
	sigBytes, err := hex.DecodeString(signature)
	if err != nil || len(sigBytes) != ed25519.SignatureSize {
		return fmt.Errorf("%w: invalid signature encoding", ErrAnchorSignature)
	}
	message, err := canonicalWithOrder(obj, order)
	if err != nil {
		return err
	}
	if !ed25519.Verify(ed25519.PublicKey(publicKey), message, sigBytes) {
		return fmt.Errorf("%w: invalid Ed25519 anchor signature", ErrAnchorSignature)
	}
	return nil
}

// VerifyLedgerReceipt verifies an anchor-signed ledger receipt.
func VerifyLedgerReceipt(receipt any, publicKeyHex string) error {
	return verifyAnchor(receipt, ledgerReceiptOrder, publicKeyHex)
}

// VerifyHistorySlice verifies an anchor-signed history projection.
func VerifyHistorySlice(slice any, publicKeyHex string) error {
	return verifyAnchor(slice, historySliceOrder, publicKeyHex)
}

// VerifyCompactionCheckpoint verifies an anchor-signed compaction checkpoint.
func VerifyCompactionCheckpoint(checkpoint any, publicKeyHex string) error {
	return verifyAnchor(checkpoint, compactionOrder, publicKeyHex)
}
