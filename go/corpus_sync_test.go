package rigorix

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/arman-jalili/rigorix-sdk/go/internal/corpus"
)

// TestEmbeddedCorpusMatchesDisk fails if corpus_gen.go drifts from the canonical
// repo-root `schemas/` (regenerate with `go generate ./...`).
func TestEmbeddedCorpusMatchesDisk(t *testing.T) {
	root := filepath.Join("..", "schemas")
	if _, err := os.Stat(filepath.Join(root, "envelope.json")); err != nil {
		t.Skip("repo schemas/ not present")
	}
	var disk []string
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		disk = append(disk, filepath.ToSlash(rel))
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	embedded := corpus.Files()
	if len(embedded) != len(disk) {
		t.Fatalf("embedded %d files, disk %d (run `go generate ./...`)", len(embedded), len(disk))
	}
	for _, rel := range disk {
		data, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(rel)))
		if err != nil {
			t.Fatal(err)
		}
		got, ok := corpus.Schema(rel)
		if !ok {
			t.Fatalf("embedded corpus missing %s", rel)
		}
		if got != string(data) {
			t.Fatalf("embedded %s differs from disk (run `go generate ./...`)", rel)
		}
	}
}
