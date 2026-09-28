package client

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
)

// Transport posts a JSON-RPC body and returns the raw response body.
type Transport interface {
	Post(ctx context.Context, body []byte) ([]byte, error)
}

// HTTPTransport posts to a URL over net/http.
type HTTPTransport struct {
	URL     string
	Headers map[string]string
	Client  *http.Client
}

// NewHTTPTransport builds an HTTP transport with optional extra headers.
func NewHTTPTransport(url string, headers map[string]string) *HTTPTransport {
	return &HTTPTransport{URL: url, Headers: headers, Client: http.DefaultClient}
}

// Post implements Transport.
func (t *HTTPTransport) Post(ctx context.Context, body []byte) ([]byte, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, t.URL, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	request.Header.Set("content-type", "application/json")
	for key, value := range t.Headers {
		request.Header.Set(key, value)
	}
	httpClient := t.Client
	if httpClient == nil {
		httpClient = http.DefaultClient
	}
	response, err := httpClient.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	data, err := io.ReadAll(response.Body)
	if err != nil {
		return nil, err
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return data, fmt.Errorf("transport: HTTP %d", response.StatusCode)
	}
	return data, nil
}

// MockTransport records requests and replays queued responses (tests).
type MockTransport struct {
	Requests  [][]byte
	Responses [][]byte
}

// Post implements Transport.
func (m *MockTransport) Post(_ context.Context, body []byte) ([]byte, error) {
	m.Requests = append(m.Requests, body)
	if len(m.Responses) == 0 {
		return nil, fmt.Errorf("mock transport: no queued response")
	}
	next := m.Responses[0]
	m.Responses = m.Responses[1:]
	return next, nil
}
