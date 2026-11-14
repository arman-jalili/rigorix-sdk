// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalali and Rigorix contributors

package gate

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"sync"

	"github.com/tetratelabs/wazero"
)

// Compiling the artifact is the whole cost of an open: wazero's CompileModule
// measures 393-425 ms for the 1.9 MB module on the machine that filed #142,
// against ~0.04 ms for the decision it enables. Compilation is a pure function
// of the bytes, so it belongs to the process.
//
// A wazero.CompiledModule is bound to the Runtime that compiled it (a module
// from another Runtime is refused with "source module must be compiled before
// instantiation"), and the six WASI imports can be defined only once per
// Runtime. So the cache entry owns both: one Runtime per artifact digest, one
// instantiation per open into that Runtime. Which is why the counters cannot
// live in the host functions' closures any more — a shared Runtime shares the
// host module, so a host function finds its gate's counters by the *calling
// instance's* name, registered by `openBytes` before instantiating.
type counterTable struct {
	mu     sync.Mutex
	byName map[string]*Counters
}

func newCounterTable() *counterTable {
	return &counterTable{byName: map[string]*Counters{}}
}

// add applies a change to the counters of one instance, if that instance is
// still open. Counters are read and written under the table's lock: the host
// functions write from the module's goroutine while the caller may be reading
// `Counters()`.
func (t *counterTable) add(name string, apply func(*Counters)) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if counters, ok := t.byName[name]; ok {
		apply(counters)
	}
}

// snapshot returns a copy of one instance's counters.
func (t *counterTable) snapshot(name string) Counters {
	t.mu.Lock()
	defer t.mu.Unlock()
	if counters, ok := t.byName[name]; ok {
		return *counters
	}
	return Counters{}
}

// has reports whether an instance is still registered.
func (t *counterTable) has(name string) bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	_, ok := t.byName[name]
	return ok
}

func (t *counterTable) put(name string, counters *Counters) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.byName[name] = counters
}

func (t *counterTable) remove(name string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	delete(t.byName, name)
}

// compiledEntry is one compiled artifact, and the Runtime it belongs to.
type compiledEntry struct {
	runtime  wazero.Runtime
	compiled wazero.CompiledModule
	counters *counterTable
	// refs counts the gates instantiating from this entry; an entry with refs
	// == 0 may be evicted, but is kept while the cache has room because that
	// is the whole point.
	refs int
	// names numbers the instances so two open gates are two modules.
	names int
}

func (e *compiledEntry) nextInstanceName() string {
	e.names++
	return fmt.Sprintf("gate-%d", e.names)
}

func (e *compiledEntry) close(ctx context.Context) {
	if e.compiled != nil {
		_ = e.compiled.Close(ctx)
	}
	if e.runtime != nil {
		_ = e.runtime.Close(ctx)
	}
}

var (
	cacheMu sync.Mutex
	cache   = map[string]*compiledEntry{}
)

// maxCompiled bounds the cache. `OpenUnverified` accepts caller-supplied bytes,
// so an unbounded digest-keyed cache is a leak with a friendly name; four is
// room for the vendored artifact plus the shapes a test or tool tries.
const maxCompiled = 4

func digestOf(wasm []byte) string {
	sum := sha256.Sum256(wasm)
	return hex.EncodeToString(sum[:])
}

// acquire returns the compiled entry for these bytes, compiling at most once
// per process and digest. The digest is also what `verifyArtifact` checks, so
// the entry for the vendored artifact is the one whose bytes were verified —
// caller bytes under `OpenUnverified` get their own entry and inherit nothing.
func acquire(ctx context.Context, wasm []byte) (*compiledEntry, error) {
	key := digestOf(wasm)

	cacheMu.Lock()
	defer cacheMu.Unlock()

	if entry, ok := cache[key]; ok {
		entry.refs++
		return entry, nil
	}

	runtime := wazero.NewRuntime(ctx)
	counters := newCounterTable()
	if _, err := hostModule(ctx, runtime, counters); err != nil {
		_ = runtime.Close(ctx)
		return nil, fmt.Errorf("gate: host imports: %w", err)
	}

	compiled, err := runtime.CompileModule(ctx, wasm)
	if err != nil {
		_ = runtime.Close(ctx)
		return nil, fmt.Errorf("%w: %v", ErrNotWASIArtifact, err)
	}
	// The shape check runs once per compile, next to the compile it describes:
	// import/export sections cannot change between instantiations.
	if err := validateCompiled(compiled); err != nil {
		_ = compiled.Close(ctx)
		_ = runtime.Close(ctx)
		return nil, err
	}

	entry := &compiledEntry{runtime: runtime, compiled: compiled, counters: counters, refs: 1}
	cache[key] = entry
	evictIdleLocked(ctx)
	return entry, nil
}

// release drops one gate's reference. An entry is closed only when the cache is
// over its bound and this entry is the one to go — a live gate's Runtime is
// never closed underneath it.
func (e *compiledEntry) release(ctx context.Context) {
	cacheMu.Lock()
	defer cacheMu.Unlock()
	if e.refs > 0 {
		e.refs--
	}
	evictIdleLocked(ctx)
}

// evictIdleLocked closes unreferenced entries while the cache is over its bound.
// If every entry is in use the cache is allowed to overshoot: evicting a live
// Runtime would break an open gate, and correctness outranks the bound.
func evictIdleLocked(ctx context.Context) {
	for len(cache) > maxCompiled {
		var (
			victimKey   string
			victimEntry *compiledEntry
		)
		for key, entry := range cache {
			if entry.refs == 0 {
				victimKey, victimEntry = key, entry
				break
			}
		}
		if victimEntry == nil {
			return
		}
		delete(cache, victimKey)
		victimEntry.close(ctx)
	}
}

// resetCompiledCache drops every entry. For tests; an open does not call it.
func resetCompiledCache(ctx context.Context) {
	cacheMu.Lock()
	defer cacheMu.Unlock()
	for key, entry := range cache {
		delete(cache, key)
		entry.close(ctx)
	}
}
