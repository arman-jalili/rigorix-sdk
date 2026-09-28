package client

import (
	"encoding/json"
	"testing"

	"github.com/arman-jalili/rigorix-sdk/go/internal/corpus"
)

// TestCatalogDrift fails if the client's binding table diverges from the frozen
// `schemas/api/catalog.json` (the namespace is closed — ADR-0001 D3).
func TestCatalogDrift(t *testing.T) {
	text, ok := corpus.Schema("api/catalog.json")
	if !ok {
		t.Fatal("catalog.json not embedded")
	}
	var doc struct {
		Methods []struct {
			Name string `json:"name"`
		} `json:"methods"`
	}
	if err := json.Unmarshal([]byte(text), &doc); err != nil {
		t.Fatal(err)
	}

	frozen := map[string]bool{}
	for _, method := range doc.Methods {
		frozen[method.Name] = true
	}
	bound := map[string]bool{}
	for _, method := range Methods {
		bound[method.Name] = true
		if !frozen[method.Name] {
			t.Errorf("bound method %s is not in the frozen catalog", method.Name)
		}
	}
	for name := range frozen {
		if !bound[name] {
			t.Errorf("frozen method %s is not bound by the client", name)
		}
	}
	if err := AssertNoRawStepExecution(); err != nil {
		t.Fatal(err)
	}
}
