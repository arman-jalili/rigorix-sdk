// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package rigorix

import "github.com/arman-jalili/rigorix-sdk/go/internal/corpus"

// Schema returns the contract at rel (relative to `schemas/`).
func Schema(rel string) (string, bool) { return corpus.Schema(rel) }

// Fixture returns the fixture at rel (relative to `schemas/fixtures/`).
func Fixture(rel string) (string, bool) { return corpus.Fixture(rel) }

// Files returns every embedded corpus path relative to `schemas/`, sorted.
func Files() []string { return corpus.Files() }
