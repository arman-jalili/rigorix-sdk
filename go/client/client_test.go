// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package client

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
)

func queued(body string) *MockTransport {
	return &MockTransport{Responses: [][]byte{[]byte(body)}}
}

func TestCallFraming(t *testing.T) {
	mock := queued(`{"jsonrpc":"2.0","id":1,"result":{"name":"rigorix"}}`)
	client := New(mock)
	raw, err := client.CallRaw(context.Background(), "rigorix.system.version", map[string]any{})
	if err != nil {
		t.Fatal(err)
	}
	if string(raw) != `{"name":"rigorix"}` {
		t.Fatalf("result: %s", raw)
	}
	var request map[string]any
	if err := json.Unmarshal(mock.Requests[0], &request); err != nil {
		t.Fatal(err)
	}
	if request["jsonrpc"] != "2.0" || request["method"] != "rigorix.system.version" {
		t.Fatalf("request: %s", mock.Requests[0])
	}
}

func TestTypedCall(t *testing.T) {
	mock := queued(`{"jsonrpc":"2.0","id":1,"result":{"name":"rigorix","engine_version":"1.7.0","api_version":"1.0.0","schemas":[],"capabilities":[]}}`)
	client := New(mock)
	version, err := client.Version(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if version.APIVersion != "1.0.0" || version.Name != "rigorix" {
		t.Fatalf("version: %+v", version)
	}
}

func TestNotificationHasNoID(t *testing.T) {
	mock := queued(`{}`)
	client := New(mock)
	if err := client.Notify(context.Background(), "rigorix.audit.read", map[string]any{"execution_id": "x"}); err != nil {
		t.Fatal(err)
	}
	var request map[string]any
	if err := json.Unmarshal(mock.Requests[0], &request); err != nil {
		t.Fatal(err)
	}
	if _, present := request["id"]; present {
		t.Fatalf("notification must not carry an id: %s", mock.Requests[0])
	}
}

func TestRPCError(t *testing.T) {
	mock := queued(`{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"method not found"}}`)
	client := New(mock)
	_, err := client.CallRaw(context.Background(), "rigorix.nope", nil)
	var rpcErr *RPCError
	if !errors.As(err, &rpcErr) || rpcErr.Code != -32601 {
		t.Fatalf("expected RPCError(-32601), got %v", err)
	}
}

func TestBatchFraming(t *testing.T) {
	mock := queued(`[{"jsonrpc":"2.0","id":1,"result":{}},{"jsonrpc":"2.0","id":2,"result":{}}]`)
	client := New(mock)
	responses, err := client.BatchRaw(context.Background(), []BatchCall{
		{Method: "rigorix.audit.list"},
		{Method: "rigorix.template.list"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(responses) != 2 {
		t.Fatalf("expected 2 responses, got %d", len(responses))
	}
	var requests []map[string]any
	if err := json.Unmarshal(mock.Requests[0], &requests); err != nil {
		t.Fatal(err)
	}
	if len(requests) != 2 || requests[0]["method"] != "rigorix.audit.list" {
		t.Fatalf("batch request: %s", mock.Requests[0])
	}
}
