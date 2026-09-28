package client

import (
	"context"
	"encoding/json"
	"fmt"
)

// ClientAPI* mirror `catalog.json` (`apiVersion`).
const (
	ClientAPIMajor   = 1
	ClientAPIVersion = "1.0.0"
)

// BatchCall is one raw call in a batch.
type BatchCall struct {
	Method string
	Params any
}

// Client is a typed JSON-RPC client over the frozen `rigorix.*` catalog.
type Client struct {
	transport Transport
	nextID    int
}

// New builds a client over a transport.
func New(transport Transport) *Client { return &Client{transport: transport, nextID: 1} }

func (c *Client) id() int {
	id := c.nextID
	c.nextID++
	return id
}

// CallRaw calls a method and returns the raw `result`.
func (c *Client) CallRaw(ctx context.Context, method string, params any) (json.RawMessage, error) {
	body, err := json.Marshal(Call(c.id(), method, params))
	if err != nil {
		return nil, err
	}
	responseBody, err := c.transport.Post(ctx, body)
	if err != nil {
		return nil, err
	}
	var response RPCResponse
	if err := json.Unmarshal(responseBody, &response); err != nil {
		return nil, err
	}
	if response.Error != nil {
		return nil, response.Error
	}
	if len(response.Result) == 0 {
		return nil, fmt.Errorf("response has neither `result` nor `error`")
	}
	return response.Result, nil
}

// CallTyped calls a method and decodes the result into R.
func CallTyped[R any](ctx context.Context, c *Client, method string, params any) (R, error) {
	var out R
	raw, err := c.CallRaw(ctx, method, params)
	if err != nil {
		return out, err
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return out, err
	}
	return out, nil
}

// Notify sends a notification (no ID; no response expected).
func (c *Client) Notify(ctx context.Context, method string, params any) error {
	body, err := json.Marshal(Notification(method, params))
	if err != nil {
		return err
	}
	_, err = c.transport.Post(ctx, body)
	return err
}

// BatchRaw sends a batch and returns the raw responses.
func (c *Client) BatchRaw(ctx context.Context, calls []BatchCall) ([]RPCResponse, error) {
	requests := make([]RPCRequest, len(calls))
	for i, entry := range calls {
		requests[i] = Call(c.id(), entry.Method, entry.Params)
	}
	body, err := json.Marshal(requests)
	if err != nil {
		return nil, err
	}
	responseBody, err := c.transport.Post(ctx, body)
	if err != nil {
		return nil, err
	}
	var responses []RPCResponse
	if err := json.Unmarshal(responseBody, &responses); err != nil {
		return nil, err
	}
	return responses, nil
}

// Version calls `rigorix.system.version`.
func (c *Client) Version(ctx context.Context) (VersionResult, error) {
	return CallTyped[VersionResult](ctx, c, "rigorix.system.version", map[string]any{})
}
