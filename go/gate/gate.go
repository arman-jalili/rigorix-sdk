// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

// Package gate loads the Rigorix WASI artifact in-process with wazero.
//
// The module decides; this package allocates the request, calls `rigx_call`,
// reads the length-prefixed response with host-side bounds checks, and returns
// the JSON. It contains no policy and no engine logic. The six WASI prologue
// imports are answered with constants and counted; any other import is a
// load-time refusal (the embedder contract).
package gate

import (
	"context"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"sync"

	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
)

//go:embed testdata/rigorix_gate_wasi.wasm
var artifact []byte

// World is the four pinned inputs `open_session` requires.
type World struct {
	Scenario any
	Fixtures any
	Clock    any
	Seed     any
}

// Action is the gated action a caller proposes.
type Action struct {
	Name   string         `json:"name"`
	Params map[string]any `json:"params,omitempty"`
}

// Counters records the three host answers that could silently become real.
// The clock must stay zero (#1477); randomness/stdout are observed counts.
type Counters struct {
	ClockTimeGetCalls int64
	RandomGetCalls    int64
	FDWriteBytes      int64
}

var (
	// ErrNotWASIArtifact means the import/export section is not the recorded one.
	ErrNotWASIArtifact = errors.New("not the WASI artifact")
	// ErrGateClosed means the session is sealed or the runtime is closed.
	ErrGateClosed = errors.New("gate session is sealed")
)

// GateError is a typed refusal from the artifact (a JSON object with `kind`).
type GateError struct {
	Kind    string
	Message string
}

func (e *GateError) Error() string { return fmt.Sprintf("gate: %s: %s", e.Kind, e.Message) }

// GateTrap is a trap, including `proc_exit`; a trap is not a refusal.
type GateTrap struct {
	Message string
}

func (e *GateTrap) Error() string { return "gate trap: " + e.Message }

// Gate is one opened session over the artifact.
//
// The compiled module and its Runtime are process-wide (see cache.go); a Gate
// owns only its instantiation, and closing it releases a reference — it cannot
// invalidate another open gate, and it does not recompile the next one.
type Gate struct {
	entry        *compiledEntry
	instanceName string
	instance     api.Module
	memory       api.Memory
	alloc        api.Function
	callFn       api.Function
	free         api.Function
	handle       any
	sealed       bool
	closed       bool
	mu           sync.Mutex
}

// Open verifies the embedded artifact's digest and size, then opens a replay
// session. Bytes that are not the recorded artifact are refused with an
// *ArtifactDigestError naming both digests.
//
// What the caller pays: the first open in a process compiles the 1.9 MB module
// (~430 ms with wazero measured on the machine that filed #142); every later
// open instantiates it into the same Runtime (~1 ms measured), because the
// compiled module is cached per artifact digest. The digest and shape checks
// run once per compile, not once per open.
func Open(ctx context.Context, world World) (*Gate, error) {
	if err := verifyArtifact(artifact); err != nil {
		return nil, err
	}
	return openBytes(ctx, artifact, world)
}

// OpenUnverified is Open over caller-supplied WebAssembly bytes, for tests and
// tooling. It checks the import/export shape but NOT the digest: the gate has
// not been checked against the recorded artifact, and the name says so.
//
// Caller bytes are cached by their own digest, so they never inherit the entry
// compiled from the vendored artifact, and identical bytes compile once per
// process however many opens they serve.
func OpenUnverified(ctx context.Context, wasm []byte, world World) (*Gate, error) {
	return openBytes(ctx, wasm, world)
}

func openBytes(ctx context.Context, wasm []byte, world World) (g *Gate, err error) {
	defer func() {
		if recovered := recover(); recovered != nil {
			g = nil
			err = trapError(recovered)
		}
	}()

	entry, err := acquire(ctx, wasm)
	if err != nil {
		return nil, err
	}

	// One host module per Runtime, one instantiation per open: the counters are
	// registered under this instance's name, which is how the shared host
	// functions find the gate whose call they are answering.
	instanceName := entry.nextInstanceName()
	entry.counters.put(instanceName, &Counters{})
	instance, err := entry.runtime.InstantiateModule(
		ctx, entry.compiled, wazero.NewModuleConfig().WithName(instanceName),
	)
	if err != nil {
		entry.counters.remove(instanceName)
		entry.release(ctx)
		return nil, fmt.Errorf("gate: instantiate: %w", err)
	}

	memory := instance.ExportedMemory("memory")
	alloc := instance.ExportedFunction("rigx_alloc")
	callFn := instance.ExportedFunction("rigx_call")
	free := instance.ExportedFunction("rigx_free")
	if memory == nil || alloc == nil || callFn == nil || free == nil {
		entry.counters.remove(instanceName)
		_ = instance.Close(ctx)
		entry.release(ctx)
		return nil, fmt.Errorf("%w: missing memory or rigx_* export", ErrNotWASIArtifact)
	}

	gate := &Gate{
		entry:        entry,
		instanceName: instanceName,
		instance:     instance,
		memory:       memory,
		alloc:        alloc,
		callFn:       callFn,
		free:         free,
	}

	opened := map[string]any{}
	request := map[string]any{
		"op":       "open_session",
		"scenario": world.Scenario,
		"fixtures": world.Fixtures,
		"clock":    world.Clock,
		"seed":     world.Seed,
	}
	if err := gate.callJSON(ctx, request, &opened); err != nil {
		_ = gate.Close(ctx)
		return nil, err
	}
	handle, ok := opened["handle"]
	if !ok {
		_ = gate.Close(ctx)
		return nil, &GateError{Kind: "request_invalid", Message: "open_session returned no handle"}
	}
	gate.handle = handle
	return gate, nil
}

// Attempt drives the session's one attempt. A refusal is an error whose Kind is
// the artifact's own refusal vocabulary.
func (g *Gate) Attempt(ctx context.Context, action Action) (map[string]any, error) {
	g.mu.Lock()
	if g.sealed {
		g.mu.Unlock()
		return nil, ErrGateClosed
	}
	handle := g.handle
	g.mu.Unlock()

	out := map[string]any{}
	request := map[string]any{
		"op":     "attempt_run",
		"handle": map[string]any{"handle": handle},
		"action": action,
	}
	if err := g.callJSON(ctx, request, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// ExportArtifactSet seals the session and returns the artifact set.
func (g *Gate) ExportArtifactSet(ctx context.Context) (map[string]any, error) {
	g.mu.Lock()
	if g.sealed {
		g.mu.Unlock()
		return nil, ErrGateClosed
	}
	handle := g.handle
	g.mu.Unlock()

	out := map[string]any{}
	request := map[string]any{
		"op":     "export_artifact_set",
		"handle": map[string]any{"handle": handle},
	}
	if err := g.callJSON(ctx, request, &out); err != nil {
		return nil, err
	}
	g.mu.Lock()
	g.sealed = true
	g.mu.Unlock()
	return out, nil
}

// ContractVersion reports the artifact's contract/engine/format numbers.
func (g *Gate) ContractVersion(ctx context.Context) (map[string]any, error) {
	out := map[string]any{}
	if err := g.callJSON(ctx, map[string]any{"op": "contract_version"}, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// Counters returns a copy of this gate's host-answer counters.
//
// They are per instance, not per process: a shared Runtime must not let one
// gate's clock reads be reported as another's (#142).
func (g *Gate) Counters() Counters {
	if g.entry == nil || g.entry.counters == nil {
		return Counters{}
	}
	return g.entry.counters.snapshot(g.instanceName)
}

// Close releases this gate's instance and its reference to the compiled module.
// It is safe to call twice, and it never closes a Runtime another gate is using.
func (g *Gate) Close(ctx context.Context) error {
	g.mu.Lock()
	if g.closed {
		g.mu.Unlock()
		return nil
	}
	g.closed = true
	g.sealed = true
	g.mu.Unlock()

	var first error
	if g.instance != nil {
		if err := g.instance.Close(ctx); err != nil {
			first = err
		}
	}
	if g.entry != nil {
		g.entry.counters.remove(g.instanceName)
		g.entry.release(ctx)
	}
	return first
}

func (g *Gate) callJSON(ctx context.Context, request any, out any) error {
	payload, err := json.Marshal(request)
	if err != nil {
		return &GateError{Kind: "request_invalid", Message: err.Error()}
	}
	raw, err := g.callRaw(ctx, payload)
	if err != nil {
		return err
	}
	var refusal struct {
		Kind    string `json:"kind"`
		Message string `json:"message"`
	}
	if err := json.Unmarshal(raw, &refusal); err == nil && refusal.Kind != "" {
		return &GateError{Kind: refusal.Kind, Message: refusal.Message}
	}
	if err := json.Unmarshal(raw, out); err != nil {
		return &GateError{Kind: "protocol", Message: err.Error()}
	}
	return nil
}

func trapError(value any) error {
	switch typed := value.(type) {
	case *GateTrap:
		return typed
	case GateTrap:
		return &typed
	case *GateError:
		return typed
	case error:
		return &GateTrap{Message: typed.Error()}
	default:
		return &GateTrap{Message: fmt.Sprint(value)}
	}
}
