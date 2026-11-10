// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package rigorix

import (
	"encoding/json"
	"fmt"
	"sort"
)

// VerifyChain verifies the strict local chain (no gap is accepted).
func VerifyChain(envelopes []map[string]any) error {
	return VerifyChainWithCheckpoints(envelopes, nil, "")
}

// VerifyChainWithCheckpoints verifies the per-producer chain, accepting a gap
// iff a valid Ed25519-signed compaction checkpoint covers it.
func VerifyChainWithCheckpoints(envelopes []map[string]any, checkpoints []map[string]any, anchorPublicKeyHex string) error {
	for _, checkpoint := range checkpoints {
		if err := VerifyCompactionCheckpoint(checkpoint, anchorPublicKeyHex); err != nil {
			return err
		}
	}

	producers := map[string][]map[string]any{}
	for _, envelope := range envelopes {
		producer, hasProducer := envelope["producer_id"].(string)
		_, hasSequence := envelope["sequence"]
		if hasProducer && producer != "" && hasSequence {
			producers[producer] = append(producers[producer], envelope)
		}
	}

	names := make([]string, 0, len(producers))
	for name := range producers {
		names = append(names, name)
	}
	sort.Strings(names)

	for _, producer := range names {
		chain := producers[producer]
		sort.SliceStable(chain, func(i, j int) bool { return seqOf(chain[i]) < seqOf(chain[j]) })
		base := seqOf(chain[0])
		if base != 0 {
			return fmt.Errorf("%w: producer '%s': chain starts at sequence %d, not genesis 0 — the earliest envelope(s) were deleted", ErrChainBroken, producer, base)
		}
		if chain[0]["prev_hash"] != nil {
			return fmt.Errorf("%w: producer '%s': genesis envelope carries a prev_hash", ErrChainBroken, producer)
		}
		for i := 0; i+1 < len(chain); i++ {
			prev, next := chain[i], chain[i+1]
			prevSequence, nextSequence := seqOf(prev), seqOf(next)
			if nextSequence <= prevSequence {
				return fmt.Errorf("%w: producer '%s': sequence not strictly increasing (%d -> %d)", ErrChainBroken, producer, prevSequence, nextSequence)
			}
			prevHash, err := EnvelopeHash(prev)
			if err != nil {
				return err
			}
			if nextSequence == prevSequence+1 {
				if strOf(next["prev_hash"]) != prevHash {
					return fmt.Errorf("%w: producer '%s': prev_hash mismatch at sequence %d", ErrChainBroken, producer, nextSequence)
				}
				continue
			}
			link := strOf(next["prev_hash"])
			if link == "" {
				return fmt.Errorf("%w: producer '%s': missing prev_hash after gap at sequence %d", ErrChainBroken, producer, nextSequence)
			}
			covered := false
			for _, checkpoint := range checkpoints {
				if intOf(checkpoint["sequence_from"]) == prevSequence+1 &&
					intOf(checkpoint["sequence_to"]) == nextSequence-1 &&
					strOf(checkpoint["prior_head"]) == prevHash &&
					strOf(checkpoint["new_head"]) == link {
					covered = true
					break
				}
			}
			if !covered {
				return fmt.Errorf("%w: producer '%s': uncovered gap sequences %d..=%d", ErrChainBroken, producer, prevSequence+1, nextSequence-1)
			}
		}
	}
	return nil
}

func seqOf(envelope map[string]any) int {
	return intOf(envelope["sequence"])
}

func intOf(value any) int {
	switch typed := value.(type) {
	case nil:
		return -1
	case int:
		return typed
	case int64:
		return int(typed)
	case float64:
		return int(typed)
	case json.Number:
		n, err := typed.Int64()
		if err != nil {
			return -1
		}
		return int(n)
	default:
		return -1
	}
}

func strOf(value any) string {
	if s, ok := value.(string); ok {
		return s
	}
	return ""
}
