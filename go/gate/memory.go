// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package gate

import (
	"context"
	"fmt"

	"github.com/tetratelabs/wazero/api"
)

// callRaw is one alloc/write/call/read/free cycle. The response lives in
// linear memory as `[len: u32 LE][payload]`; the host, not the module, checks
// the length against the memory before reading (#1472).
func (g *Gate) callRaw(ctx context.Context, request []byte) (raw []byte, err error) {
	defer func() {
		if recovered := recover(); recovered != nil {
			raw = nil
			err = trapError(recovered)
		}
	}()

	g.mu.Lock()
	defer g.mu.Unlock()
	if g.runtimeClosed {
		return nil, ErrGateClosed
	}

	ptr, err := callU32(ctx, g.alloc, uint64(len(request)))
	if err != nil {
		return nil, err
	}
	if ptr == 0 {
		return nil, &GateError{Kind: "protocol", Message: "rigx_alloc refused the request buffer"}
	}
	defer func() {
		_, _ = g.free.Call(ctx, uint64(ptr), uint64(len(request)))
	}()

	if !g.memory.Write(ptr, request) {
		return nil, &GateError{Kind: "protocol", Message: "the request buffer is out of memory"}
	}

	result, err := g.callFn.Call(ctx, uint64(ptr), uint64(len(request)))
	if err != nil {
		return nil, trapError(err)
	}
	if len(result) != 1 {
		return nil, &GateError{Kind: "protocol", Message: "rigx_call returned no pointer"}
	}
	responsePtr := uint32(result[0])
	if responsePtr == 0 {
		return nil, &GateError{Kind: "protocol", Message: "rigx_call produced no response"}
	}

	size := uint64(g.memory.Size())
	if uint64(responsePtr)+4 > size {
		return nil, &GateError{
			Kind:    "protocol",
			Message: fmt.Sprintf("the response pointer %d leaves no length prefix in %d bytes", responsePtr, size),
		}
	}
	length, ok := g.memory.ReadUint32Le(responsePtr)
	if !ok {
		return nil, &GateError{Kind: "protocol", Message: "the response length is out of memory"}
	}
	if uint64(responsePtr)+4+uint64(length) > size {
		return nil, &GateError{
			Kind: "protocol",
			Message: fmt.Sprintf(
				"the response claims %d bytes at %d, but only %d remain",
				length, responsePtr, size-uint64(responsePtr)-4,
			),
		}
	}
	data, ok := g.memory.Read(responsePtr+4, length)
	if !ok {
		return nil, &GateError{Kind: "protocol", Message: "the response payload is out of memory"}
	}
	raw = append([]byte(nil), data...)
	_, _ = g.free.Call(ctx, uint64(responsePtr), uint64(length)+4)
	return raw, nil
}

func callU32(ctx context.Context, function api.Function, params ...uint64) (uint32, error) {
	result, err := function.Call(ctx, params...)
	if err != nil {
		return 0, trapError(err)
	}
	if len(result) != 1 {
		return 0, &GateError{Kind: "protocol", Message: "the exported function returned no value"}
	}
	return uint32(result[0]), nil
}
