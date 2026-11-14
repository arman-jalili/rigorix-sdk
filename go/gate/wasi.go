// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package gate

import (
	"context"
	"encoding/binary"
	"fmt"

	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
)

// expectedImports is the embedder contract's exact import set. `std` on
// wasm32-wasip1 links these six; no decision reads them.
var expectedImports = map[string]bool{
	"wasi_snapshot_preview1::environ_get":       true,
	"wasi_snapshot_preview1::environ_sizes_get": true,
	"wasi_snapshot_preview1::clock_time_get":    true,
	"wasi_snapshot_preview1::random_get":        true,
	"wasi_snapshot_preview1::fd_write":          true,
	"wasi_snapshot_preview1::proc_exit":         true,
}

// validateCompiled refuses anything whose import/export section is not the
// recorded one. An unused capability is still a capability: a seventh import
// is a load error, named, in the same commit that adds it to the record.
func validateCompiled(compiled wazero.CompiledModule) error {
	if len(compiled.ImportedMemories()) > 0 {
		return fmt.Errorf("%w: imports a memory", ErrNotWASIArtifact)
	}

	seen := map[string]bool{}
	for _, function := range compiled.ImportedFunctions() {
		moduleName, name, imported := function.Import()
		if !imported {
			return fmt.Errorf("%w: malformed import %s::%s", ErrNotWASIArtifact, moduleName, name)
		}
		key := moduleName + "::" + name
		if !expectedImports[key] {
			return fmt.Errorf("%w: unexpected import %s", ErrNotWASIArtifact, key)
		}
		seen[key] = true
	}
	for key := range expectedImports {
		if !seen[key] {
			return fmt.Errorf("%w: missing import %s", ErrNotWASIArtifact, key)
		}
	}

	for _, name := range []string{"rigx_alloc", "rigx_call", "rigx_free"} {
		if _, ok := compiled.ExportedFunctions()[name]; !ok {
			return fmt.Errorf("%w: missing export %s", ErrNotWASIArtifact, name)
		}
	}
	if _, ok := compiled.ExportedMemories()["memory"]; !ok {
		return fmt.Errorf("%w: missing export memory", ErrNotWASIArtifact)
	}
	return nil
}

// hostModule defines the six constants. The clock is counted and zeroed
// (#1477); randomness is left zeroed; stdout is discarded and counted;
// proc_exit becomes a typed trap, never the caller's process exit.
//
// The counters arrive through the table, keyed by the calling instance's name:
// one Runtime is shared by every gate compiled from the same bytes (#142), so a
// closure per open would be answered to whichever gate defined it last.
func hostModule(ctx context.Context, runtime wazero.Runtime, counters *counterTable) (api.Module, error) {
	builder := runtime.NewHostModuleBuilder("wasi_snapshot_preview1")

	builder.NewFunctionBuilder().WithFunc(
		func(_ context.Context, _ api.Module, environPtr, environBuf uint32) uint32 {
			return 0
		},
	).Export("environ_get")

	builder.NewFunctionBuilder().WithFunc(
		func(_ context.Context, module api.Module, environc, environBufSize uint32) uint32 {
			if memory := module.Memory(); memory != nil {
				memory.WriteUint32Le(environc, 0)
				memory.WriteUint32Le(environBufSize, 0)
			}
			return 0
		},
	).Export("environ_sizes_get")

	builder.NewFunctionBuilder().WithFunc(
		func(_ context.Context, module api.Module, clockID uint32, precision uint64, timePtr uint32) uint32 {
			if memory := module.Memory(); memory != nil {
				memory.WriteUint64Le(timePtr, 0)
			}
			counters.add(module.Name(), func(c *Counters) { c.ClockTimeGetCalls++ })
			return 0
		},
	).Export("clock_time_get")

	builder.NewFunctionBuilder().WithFunc(
		func(_ context.Context, module api.Module, bufPtr, bufLen uint32) uint32 {
			counters.add(module.Name(), func(c *Counters) { c.RandomGetCalls++ })
			return 0
		},
	).Export("random_get")

	builder.NewFunctionBuilder().WithFunc(
		func(_ context.Context, module api.Module, fd, iovs, iovsLen, nwritten uint32) uint32 {
			memory := module.Memory()
			if memory == nil {
				return 0
			}
			var total int64
			for index := uint32(0); index < iovsLen; index++ {
				raw, ok := memory.Read(iovs+index*8, 8)
				if !ok {
					break
				}
				total += int64(binary.LittleEndian.Uint32(raw[4:8]))
			}
			counters.add(module.Name(), func(c *Counters) { c.FDWriteBytes += total })
			memory.WriteUint32Le(nwritten, 0)
			return 0
		},
	).Export("fd_write")

	builder.NewFunctionBuilder().WithFunc(
		func(_ context.Context, _ api.Module, code uint32) {
			panic(&GateTrap{Message: fmt.Sprintf("the module called proc_exit(%d)", code)})
		},
	).Export("proc_exit")

	return builder.Instantiate(ctx)
}
