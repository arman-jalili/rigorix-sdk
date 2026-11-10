// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package rigorix

import "errors"

// Verifier error taxonomy (mirrors the Rust `VerifyError`).
var (
	ErrSignatureMismatch   = errors.New("signature mismatch")
	ErrUnsignedNotDegraded = errors.New("unsigned envelope without evidence_degraded=true (GAP-M-12 violation)")
	ErrSchemaViolation     = errors.New("schema violation")
	ErrChainBroken         = errors.New("chain broken")
	ErrAnchorSignature     = errors.New("invalid anchor signature")
)
