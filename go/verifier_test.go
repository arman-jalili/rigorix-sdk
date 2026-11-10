// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package rigorix

import (
	"bytes"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/arman-jalili/rigorix-sdk/go/internal/corpus"
)

const (
	fixtureKey      = "fixture-hmac-key-2026"
	anchorPublicKey = "ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c"
)

func fixtureNames(prefix string) []string {
	needle := "fixtures/" + prefix + "/"
	var out []string
	for _, name := range corpus.Files() {
		if strings.HasPrefix(name, needle) && strings.HasSuffix(name, ".json") {
			out = append(out, strings.TrimPrefix(name, needle))
		}
	}
	return out
}

func readFixture(t *testing.T, rel string) string {
	t.Helper()
	text, ok := corpus.Fixture(rel)
	if !ok {
		t.Fatalf("fixture %s not embedded", rel)
	}
	return text
}

func decodeInto(t *testing.T, data []byte, dest any) {
	t.Helper()
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	if err := dec.Decode(dest); err != nil {
		t.Fatal(err)
	}
}

func readMap(t *testing.T, rel string) map[string]any {
	t.Helper()
	var out map[string]any
	decodeInto(t, []byte(readFixture(t, rel)), &out)
	return out
}

func readChain(t *testing.T, name string) []map[string]any {
	t.Helper()
	var out []map[string]any
	decodeInto(t, []byte(readFixture(t, "integrity/"+name)), &out)
	return out
}

func TestSignedEngineFixturesVerifyByteExact(t *testing.T) {
	signed := 0
	for _, name := range fixtureNames("envelope") {
		text := readFixture(t, "envelope/"+name)
		var data map[string]any
		decodeInto(t, []byte(text), &data)
		if data["signature"] == nil {
			continue
		}
		if err := VerifySignature(text, fixtureKey); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if err := ValidateEnvelope(text); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		signed++
	}
	if signed < 3 {
		t.Fatalf("expected >= 3 signed fixtures, found %d", signed)
	}
}

func TestAnchoredFixtureBindsAnchorHead(t *testing.T) {
	text := readFixture(t, "envelope/envelope-anchored-signed.json")
	var data map[string]any
	decodeInto(t, []byte(text), &data)
	if data["history_integrity"] != "anchored" {
		t.Fatalf("expected anchored, got %v", data["history_integrity"])
	}
	if data["anchor_head"] == nil {
		t.Fatal("anchor_head must be non-null")
	}
	if approvals, _ := data["approval_events"].([]any); len(approvals) == 0 {
		t.Fatal("fixture must carry approval_events (position proof)")
	}
	if err := VerifySignature(text, fixtureKey); err != nil {
		t.Fatalf("anchored fixture: %v", err)
	}
	canonical, err := CanonicalBytes(text)
	if err != nil {
		t.Fatal(err)
	}
	headAt := strings.Index(string(canonical), `"anchor_head"`)
	approvalsAt := strings.Index(string(canonical), `"approval_events"`)
	if headAt < 0 || approvalsAt < 0 || headAt > approvalsAt {
		t.Fatalf("anchor_head must precede approval_events in the signed bytes")
	}
	// Tampering with the head is detected.
	data["anchor_head"] = strings.Repeat("0", 64)
	raw, _ := json.Marshal(data)
	if err := VerifySignature(raw, fixtureKey); !errors.Is(err, ErrSignatureMismatch) {
		t.Fatalf("tamper not detected: %v", err)
	}
}

// TestPreconditionFindingsFixture covers ADR-017: the contract-first
// precondition fixture verifies byte-exact and is tamper-detected.
func TestPreconditionFindingsFixture(t *testing.T) {
	text := readFixture(t, "envelope/envelope-precondition-signed.json")
	var data map[string]any
	decodeInto(t, []byte(text), &data)
	findings, ok := data["precondition_findings"].([]any)
	if !ok || len(findings) != 4 {
		t.Fatalf("expected 4 precondition findings")
	}
	first := findings[0].(map[string]any)
	if first["outcome"] != "failed" || intOf(first["exit_code"]) != 3 {
		t.Fatalf("finding[0]: %v", first)
	}
	second := findings[1].(map[string]any)
	if second["outcome"] != "passed" || intOf(second["exit_code"]) != 0 {
		t.Fatalf("finding[1]: %v", second)
	}
	third := findings[2].(map[string]any)
	if third["outcome"] != "error" || third["exit_code"] != nil {
		t.Fatalf("finding[2]: %v", third)
	}
	fourth := findings[3].(map[string]any)
	if fourth["outcome"] != "failed" || intOf(fourth["exit_code"]) != 5 {
		t.Fatalf("finding[3]: %v", fourth)
	}
	// ISSUE-ATTRIBUTION-ABSENCE-REASON: the four states are distinct.
	wantAttribution := []string{"recorded", "recorded", "refused_before_check", "artifact_unreadable"}
	for i, want := range wantAttribution {
		if findings[i].(map[string]any)["attribution"] != want {
			t.Fatalf("finding[%d] attribution: got %v want %q", i, findings[i].(map[string]any)["attribution"], want)
		}
	}
	if _, present := third["check_digest"]; present {
		t.Fatalf("refused finding must omit check_digest")
	}

	if err := VerifySignature(text, fixtureKey); err != nil {
		t.Fatal(err)
	}
	if err := ValidateEnvelope(text); err != nil {
		t.Fatal(err)
	}

	first["inputs_hash"] = strings.Repeat("0", 64)
	raw, _ := json.Marshal(data)
	if err := VerifySignature(raw, fixtureKey); !errors.Is(err, ErrSignatureMismatch) {
		t.Fatalf("tamper not detected: %v", err)
	}

	legacy := readFixture(t, "envelope/envelope-minimal-signed.json")
	if strings.Contains(legacy, "precondition_findings") {
		t.Fatal("legacy fixture must not carry precondition_findings")
	}
	if err := VerifySignature(legacy, fixtureKey); err != nil {
		t.Fatal(err)
	}
}

func TestTamperingDetected(t *testing.T) {
	var data map[string]any
	decodeInto(t, []byte(readFixture(t, "envelope/envelope-minimal-signed.json")), &data)
	data["total_tokens"] = json.Number("999999")
	raw, _ := json.Marshal(data)
	if err := VerifySignature(raw, fixtureKey); !errors.Is(err, ErrSignatureMismatch) {
		t.Fatalf("expected SignatureMismatch, got %v", err)
	}
}

func TestUnsignedMustBeDegraded(t *testing.T) {
	var data map[string]any
	decodeInto(t, []byte(readFixture(t, "envelope/envelope-unsigned-degraded.json")), &data)
	data["evidence_degraded"] = false
	raw, _ := json.Marshal(data)
	if err := VerifySignature(raw, fixtureKey); !errors.Is(err, ErrUnsignedNotDegraded) {
		t.Fatalf("expected UnsignedNotDegraded, got %v", err)
	}
}

func TestValidChainVerifies(t *testing.T) {
	if err := VerifyChain(readChain(t, "chain.json")); err != nil {
		t.Fatal(err)
	}
}

func TestBrokenChainRejected(t *testing.T) {
	if err := VerifyChain(readChain(t, "broken-chain.json")); !errors.Is(err, ErrChainBroken) {
		t.Fatalf("expected ChainBroken, got %v", err)
	}
}

func TestAlteredPredecessorRejected(t *testing.T) {
	chain := readChain(t, "chain.json")
	chain[len(chain)-1]["prev_hash"] = strings.Repeat("0", 64)
	if err := VerifyChain(chain); !errors.Is(err, ErrChainBroken) {
		t.Fatalf("expected ChainBroken, got %v", err)
	}
}

func TestDuplicateSequenceRejected(t *testing.T) {
	chain := readChain(t, "chain.json")
	chain[len(chain)-1]["sequence"] = chain[len(chain)-2]["sequence"]
	if err := VerifyChain(chain); !errors.Is(err, ErrChainBroken) {
		t.Fatalf("expected ChainBroken, got %v", err)
	}
}

func TestCheckpointCoversGap(t *testing.T) {
	broken := readChain(t, "broken-chain.json")
	checkpoint := readMap(t, "integrity/compaction-checkpoint.json")
	if err := VerifyChain(broken); !errors.Is(err, ErrChainBroken) {
		t.Fatalf("expected broken chain, got %v", err)
	}
	if err := VerifyChainWithCheckpoints(broken, []map[string]any{checkpoint}, anchorPublicKey); err != nil {
		t.Fatalf("checkpoint must cover the gap: %v", err)
	}
}

func TestForgedCheckpointRejected(t *testing.T) {
	broken := readChain(t, "broken-chain.json")
	forged := readMap(t, "integrity/compaction-checkpoint.json")
	forged["new_head"] = strings.Repeat("0", 64)
	err := VerifyChainWithCheckpoints(broken, []map[string]any{forged}, anchorPublicKey)
	if !errors.Is(err, ErrAnchorSignature) {
		t.Fatalf("expected AnchorSignature, got %v", err)
	}
}

func TestAnchorArtifactsVerify(t *testing.T) {
	if err := VerifyLedgerReceipt(readMap(t, "integrity/ledger-receipt.json"), anchorPublicKey); err != nil {
		t.Fatalf("ledger receipt: %v", err)
	}
	if err := VerifyHistorySlice(readMap(t, "integrity/history-slice.json"), anchorPublicKey); err != nil {
		t.Fatalf("history slice: %v", err)
	}
	if err := VerifyCompactionCheckpoint(readMap(t, "integrity/compaction-checkpoint.json"), anchorPublicKey); err != nil {
		t.Fatalf("compaction checkpoint: %v", err)
	}
}

func TestHistorySliceTamperRejected(t *testing.T) {
	slice := readMap(t, "integrity/history-slice.json")
	actions, ok := slice["actions"].([]any)
	if !ok || len(actions) == 0 {
		t.Fatal("history slice must carry actions")
	}
	actions[0].(map[string]any)["node"] = "forged_node"
	if err := VerifyHistorySlice(slice, anchorPublicKey); !errors.Is(err, ErrAnchorSignature) {
		t.Fatalf("expected AnchorSignature, got %v", err)
	}
}
