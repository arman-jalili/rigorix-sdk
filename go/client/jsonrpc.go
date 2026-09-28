package client

import (
	"encoding/json"
	"fmt"
)

// RPCRequest is a JSON-RPC 2.0 request (or notification when ID is nil).
type RPCRequest struct {
	JSONRPC string `json:"jsonrpc"`
	Method  string `json:"method"`
	Params  any    `json:"params,omitempty"`
	ID      any    `json:"id,omitempty"`
}

// RPCError is a JSON-RPC 2.0 error object.
type RPCError struct {
	Code    int             `json:"code"`
	Message string          `json:"message"`
	Data    json.RawMessage `json:"data,omitempty"`
}

func (e *RPCError) Error() string {
	return fmt.Sprintf("jsonrpc error %d: %s", e.Code, e.Message)
}

// RPCResponse is a JSON-RPC 2.0 response.
type RPCResponse struct {
	JSONRPC string          `json:"jsonrpc,omitempty"`
	ID      any             `json:"id,omitempty"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *RPCError       `json:"error,omitempty"`
}

// Call builds a request expecting a response.
func Call(id any, method string, params any) RPCRequest {
	return RPCRequest{JSONRPC: "2.0", Method: method, Params: params, ID: id}
}

// Notification builds a request with no ID (no response expected).
func Notification(method string, params any) RPCRequest {
	return RPCRequest{JSONRPC: "2.0", Method: method, Params: params}
}
