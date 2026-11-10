// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package client

import "fmt"

// ProtocolError is a malformed JSON-RPC response, or a response that is not an
// answer to the request (missing result, mismatched id).
type ProtocolError struct {
	Message string
}

func (e *ProtocolError) Error() string { return e.Message }

// TransportError is a network/IO failure or a non-2xx HTTP response. It is not
// an RPC error: the host did not answer, as opposed to refusing.
type TransportError struct {
	Message string
}

func (e *TransportError) Error() string { return e.Message }

// VersionMismatchError reports an `api_version` major the client does not speak.
type VersionMismatchError struct {
	Server      string
	ClientMajor int
}

func (e *VersionMismatchError) Error() string {
	return fmt.Sprintf(
		"server apiVersion %s is incompatible with the client constraint (major %d)",
		e.Server, e.ClientMajor,
	)
}
