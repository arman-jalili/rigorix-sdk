// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package gate

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tetratelabs/wazero"
)

type vector struct {
	ID               string         `json:"id"`
	Scenario         map[string]any `json:"scenario"`
	Fixtures         any            `json:"fixtures"`
	Clock            any            `json:"clock"`
	Seed             any            `json:"seed"`
	SeededDivergence bool           `json:"seeded_divergence"`
	ExpectedDecision struct {
		Hex    string `json:"hex"`
		SHA256 string `json:"sha256"`
	} `json:"expected_decision"`
}

func loadVector(t *testing.T, id string) vector {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("testdata", "vectors", id+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var v vector
	if err := json.Unmarshal(data, &v); err != nil {
		t.Fatal(err)
	}
	return v
}

func actionOf(t *testing.T, v vector) Action {
	t.Helper()
	raw, err := json.Marshal(v.Scenario["action"])
	if err != nil {
		t.Fatal(err)
	}
	var action Action
	if err := json.Unmarshal(raw, &action); err != nil {
		t.Fatal(err)
	}
	return action
}

func openVector(t *testing.T, v vector) *Gate {
	t.Helper()
	g, err := Open(context.Background(), World{
		Scenario: v.Scenario,
		Fixtures: v.Fixtures,
		Clock:    v.Clock,
		Seed:     v.Seed,
	})
	if err != nil {
		t.Fatalf("%s: open: %v", v.ID, err)
	}
	t.Cleanup(func() { _ = g.Close(context.Background()) })
	return g
}

func expectedCanonical(t *testing.T, hexValue string) string {
	t.Helper()
	raw, err := hex.DecodeString(hexValue)
	if err != nil {
		t.Fatal(err)
	}
	return base64.StdEncoding.EncodeToString(raw)
}

func TestConformance(t *testing.T) {
	entries, err := os.ReadDir(filepath.Join("testdata", "vectors"))
	if err != nil {
		t.Fatal(err)
	}
	paths := make([]string, 0, len(entries))
	for _, entry := range entries {
		if strings.HasSuffix(entry.Name(), ".json") {
			paths = append(paths, filepath.Join("testdata", "vectors", entry.Name()))
		}
	}
	if len(paths) != 5 {
		t.Fatalf("found %d vectors; the artifact claims five", len(paths))
	}

	ctx := context.Background()
	for _, path := range paths {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		var v vector
		if err := json.Unmarshal(data, &v); err != nil {
			t.Fatal(err)
		}
		g := openVector(t, v)
		out, err := g.Attempt(ctx, actionOf(t, v))
		if err != nil {
			t.Fatalf("%s: attempt: %v", v.ID, err)
		}
		matched := out["decision_digest"] == v.ExpectedDecision.SHA256 &&
			out["decision_canonical"] == expectedCanonical(t, v.ExpectedDecision.Hex)
		if v.SeededDivergence {
			if matched {
				t.Fatalf("%s must diverge from the recorded decision", v.ID)
			}
		} else if !matched {
			t.Fatalf("%s: digest %v != %s", v.ID, out["decision_digest"], v.ExpectedDecision.SHA256)
		}

		if _, err := g.ExportArtifactSet(ctx); err != nil {
			t.Fatalf("%s: seal: %v", v.ID, err)
		}
		counters := g.Counters()
		if counters.ClockTimeGetCalls != 0 {
			t.Fatalf("%s: the decision read the clock %d time(s)", v.ID, counters.ClockTimeGetCalls)
		}
		if counters.FDWriteBytes != 0 {
			t.Fatalf("%s: the decision wrote %d byte(s) to stdout", v.ID, counters.FDWriteBytes)
		}
	}
}

func TestCapacityOperands(t *testing.T) {
	v := loadVector(t, "vec-0002")
	g := openVector(t, v)
	out, err := g.Attempt(context.Background(), actionOf(t, v))
	if err != nil {
		t.Fatal(err)
	}
	steps, ok := out["steps"].([]any)
	if !ok || len(steps) == 0 {
		t.Fatalf("steps: %#v", out["steps"])
	}
	step, ok := steps[0].(map[string]any)
	if !ok {
		t.Fatalf("step: %#v", steps[0])
	}
	detail, ok := step["detail"].(map[string]any)
	if !ok {
		t.Fatalf("detail: %#v", step["detail"])
	}
	if step["kind"] != "capacity_exceeded" {
		t.Fatalf("kind = %v", step["kind"])
	}
	if detail["overage"] != float64(7420) || detail["claimed"] != float64(1427420) {
		t.Fatalf("operands: %#v", detail)
	}
}

func TestDuplicateEffectOperands(t *testing.T) {
	v := loadVector(t, "vec-0003")
	g := openVector(t, v)
	out, err := g.Attempt(context.Background(), actionOf(t, v))
	if err != nil {
		t.Fatal(err)
	}
	steps := out["steps"].([]any)
	step := steps[0].(map[string]any)
	detail := step["detail"].(map[string]any)
	if step["kind"] != "duplicate_effect" {
		t.Fatalf("kind = %v", step["kind"])
	}
	if detail["record_id"] != "QR-2041" {
		t.Fatalf("record_id = %v", detail["record_id"])
	}
}

func TestSealedSessionRefusesAStaleHandle(t *testing.T) {
	v := loadVector(t, "vec-0001")
	g := openVector(t, v)
	ctx := context.Background()
	if _, err := g.Attempt(ctx, actionOf(t, v)); err != nil {
		t.Fatal(err)
	}
	if _, err := g.ExportArtifactSet(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := g.Attempt(ctx, actionOf(t, v)); !errors.Is(err, ErrGateClosed) {
		t.Fatalf("attempt after seal: %v", err)
	}
	if _, err := g.ExportArtifactSet(ctx); !errors.Is(err, ErrGateClosed) {
		t.Fatalf("seal after seal: %v", err)
	}
}

func TestTruncatedRequestIsTypedAndInstanceSurvives(t *testing.T) {
	v := loadVector(t, "vec-0001")
	g := openVector(t, v)
	ctx := context.Background()
	raw, err := g.callRaw(ctx, []byte(`{"op":"attempt_run","handle":{"hand`))
	if err != nil {
		t.Fatal(err)
	}
	var refusal map[string]any
	if err := json.Unmarshal(raw, &refusal); err != nil {
		t.Fatal(err)
	}
	if refusal["kind"] != "request_invalid" {
		t.Fatalf("refusal: %#v", refusal)
	}
	if _, err := g.ContractVersion(ctx); err != nil {
		t.Fatalf("the instance stopped answering: %v", err)
	}
}

func TestUnknownOpIsTyped(t *testing.T) {
	v := loadVector(t, "vec-0001")
	g := openVector(t, v)
	raw, err := g.callRaw(context.Background(), []byte(`{"op":"nope"}`))
	if err != nil {
		t.Fatal(err)
	}
	var refusal map[string]any
	if err := json.Unmarshal(raw, &refusal); err != nil {
		t.Fatal(err)
	}
	if refusal["kind"] != "request_invalid" {
		t.Fatalf("refusal: %#v", refusal)
	}
}

func TestUnexpectedImportIsRefusedByName(t *testing.T) {
	_, err := OpenUnverified(context.Background(), wasmWithImport(
		"__wbindgen_placeholder__", "__wbindgen_throw",
	), World{})
	if !errors.Is(err, ErrNotWASIArtifact) {
		t.Fatalf("expected ErrNotWASIArtifact, got %v", err)
	}
	if !strings.Contains(err.Error(), "__wbindgen_placeholder__") {
		t.Fatalf("the refusal must name the import: %v", err)
	}
}

func TestAModifiedArtifactIsRefusedAtLoad(t *testing.T) {
	// `Open` calls verifyArtifact before compiling; flipping one byte is the
	// attack the check exists for, and both digests must be named.
	edited := append([]byte(nil), artifact...)
	edited[len(edited)/2] ^= 0xff

	err := verifyArtifact(edited)
	if err == nil {
		t.Fatal("a modified artifact must be refused")
	}
	var refusal *ArtifactDigestError
	if !errors.As(err, &refusal) {
		t.Fatalf("expected *ArtifactDigestError, got %T: %v", err, err)
	}
	if !errors.Is(err, ErrArtifactDigestMismatch) {
		t.Fatalf("errors.Is(err, ErrArtifactDigestMismatch) must hold: %v", err)
	}
	if refusal.Expected != artifactSHA256 {
		t.Fatalf("expected digest = %s, want %s", refusal.Expected, artifactSHA256)
	}
	sum := fmt.Sprintf("%x", sha256.Sum256(edited))
	if refusal.Actual != sum {
		t.Fatalf("actual digest = %s, want %s", refusal.Actual, sum)
	}
	// The operator quotes the message, not the struct.
	if !strings.Contains(err.Error(), artifactSHA256) || !strings.Contains(err.Error(), sum) {
		t.Fatalf("the refusal must name both digests: %v", err)
	}
	if refusal.ExpectedSize != artifactSize || refusal.ActualSize != len(edited) {
		t.Fatalf("sizes = %d/%d, want %d/%d",
			refusal.ExpectedSize, refusal.ActualSize, artifactSize, len(edited))
	}
}

func TestVerifyArtifactAcceptsTheRecordedBytes(t *testing.T) {
	if err := verifyArtifact(artifact); err != nil {
		t.Fatalf("the recorded artifact must verify: %v", err)
	}
}

func TestVerifyArtifactRefusesATruncation(t *testing.T) {
	err := verifyArtifact(artifact[:len(artifact)-1])
	if !errors.Is(err, ErrArtifactDigestMismatch) {
		t.Fatalf("a truncation must be a digest refusal, got %v", err)
	}
}

func TestCallerBytesOpenThroughTheUnverifiedEntryPoint(t *testing.T) {
	v := loadVector(t, "vec-0001")
	g, err := OpenUnverified(context.Background(), artifact, World{
		Scenario: v.Scenario,
		Fixtures: v.Fixtures,
		Clock:    v.Clock,
		Seed:     v.Seed,
	})
	if err != nil {
		t.Fatalf("OpenUnverified over the honest bytes: %v", err)
	}
	defer g.Close(context.Background())
	out, err := g.Attempt(context.Background(), actionOf(t, v))
	if err != nil {
		t.Fatalf("attempt: %v", err)
	}
	if out["decision_digest"] != v.ExpectedDecision.SHA256 {
		t.Fatalf("digest %v != %s", out["decision_digest"], v.ExpectedDecision.SHA256)
	}
}

func TestArtifactDigest(t *testing.T) {
	sum := fmt.Sprintf("%x", sha256.Sum256(artifact))
	provenance, err := os.ReadFile(filepath.Join("testdata", "PROVENANCE.md"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(provenance), sum) {
		t.Fatalf("PROVENANCE.md does not record the artifact digest %s", sum)
	}
	// The load-time check and the record are one fact, not two copies of it.
	if sum != artifactSHA256 {
		t.Fatalf("artifactSHA256 = %s, bytes hash to %s", artifactSHA256, sum)
	}
	if len(artifact) != artifactSize {
		t.Fatalf("artifact size = %d, want %d", len(artifact), artifactSize)
	}
}

func TestImportRecordIsSix(t *testing.T) {
	ctx := context.Background()
	runtime := wazero.NewRuntime(ctx)
	defer runtime.Close(ctx)
	compiled, err := runtime.CompileModule(ctx, artifact)
	if err != nil {
		t.Fatal(err)
	}
	defer compiled.Close(ctx)

	imports := compiled.ImportedFunctions()
	if len(imports) != len(expectedImports) || len(expectedImports) != 6 {
		t.Fatalf("imports = %d, expected = %d", len(imports), len(expectedImports))
	}
	for _, function := range imports {
		moduleName, name, _ := function.Import()
		key := moduleName + "::" + name
		if !expectedImports[key] {
			t.Fatalf("unrecorded import %s", key)
		}
	}
}

func TestNoPolicyInGo(t *testing.T) {
	forbidden := []string{
		"payment_execute",
		"capacity_exceeded",
		"duplicate_effect",
		"overage",
		"eligibility.check",
		"budget.check",
	}
	for _, name := range []string{"gate.go", "wasi.go", "memory.go"} {
		data, err := os.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		for _, term := range forbidden {
			if bytes.Contains(data, []byte(term)) {
				t.Fatalf("%s contains policy term %q", name, term)
			}
		}
	}
}

func TestContractVersion(t *testing.T) {
	v := loadVector(t, "vec-0001")
	g := openVector(t, v)
	version, err := g.ContractVersion(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if version["contract"] != "1.14.3" {
		t.Fatalf("contract = %v", version["contract"])
	}
	if version["gate_evaluation"] != true {
		t.Fatalf("gate_evaluation = %v", version["gate_evaluation"])
	}
}

// wasmWithImport builds a minimal valid module with one function import. The
// loader must refuse it before instantiation and name the import.
func wasmWithImport(module, field string) []byte {
	var buf bytes.Buffer
	buf.Write([]byte{0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00}) // magic + version
	buf.Write([]byte{0x01, 0x04, 0x01, 0x60, 0x00, 0x00})             // type: () -> ()

	payload := []byte{0x01, byte(len(module))}
	payload = append(payload, module...)
	payload = append(payload, byte(len(field)))
	payload = append(payload, field...)
	payload = append(payload, 0x00, 0x00) // kind func, type index 0

	buf.Write([]byte{0x02, byte(len(payload))})
	buf.Write(payload)
	return buf.Bytes()
}
