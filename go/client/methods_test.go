package client

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

const versionBody = `{"jsonrpc":"2.0","id":1,"result":{"name":"rigorix","engine_version":"1.7.0","api_version":"1.0.0","schemas":[],"capabilities":[]}}`

// TestTypedMethods proves every typed wrapper exists and puts the frozen
// method name on the wire. `Version` is covered separately because it parses
// the result and enforces the major.
func TestTypedMethods(t *testing.T) {
	ctx := context.Background()
	cases := []struct {
		name   string
		method string
		call   func(*Client) error
	}{
		{"plan", "rigorix.plan", func(c *Client) error {
			_, err := c.Plan(ctx, PlanParams{TemplateName: "t"})
			return err
		}},
		{"validatePlan", "rigorix.validatePlan", func(c *Client) error {
			_, err := c.ValidatePlan(ctx, ValidatePlanParams{Plan: map[string]any{}})
			return err
		}},
		{"run", "rigorix.run", func(c *Client) error {
			_, err := c.Run(ctx, RunParams{TemplateName: "t"})
			return err
		}},
		{"execute", "rigorix.execute", func(c *Client) error {
			_, err := c.Execute(ctx, ExecuteParams{TemplateName: "t"})
			return err
		}},
		{"approve", "rigorix.approve", func(c *Client) error {
			_, err := c.Approve(ctx, ApproveParams{ExecutionID: "e", StepNames: []string{"s"}})
			return err
		}},
		{"checkEnforcement", "rigorix.checkEnforcement", func(c *Client) error {
			_, err := c.CheckEnforcement(ctx)
			return err
		}},
		{"audit.read", "rigorix.audit.read", func(c *Client) error {
			_, err := c.AuditRead(ctx, AuditReadParams{ExecutionID: "e"})
			return err
		}},
		{"audit.list", "rigorix.audit.list", func(c *Client) error {
			_, err := c.AuditList(ctx, AuditListParams{})
			return err
		}},
		{"audit.summary", "rigorix.audit.summary", func(c *Client) error {
			_, err := c.AuditSummary(ctx, AuditSummaryParams{})
			return err
		}},
		{"template.list", "rigorix.template.list", func(c *Client) error {
			_, err := c.TemplateList(ctx, TemplateListParams{})
			return err
		}},
		{"template.get", "rigorix.template.get", func(c *Client) error {
			_, err := c.TemplateGet(ctx, TemplateGetParams{Name: "t"})
			return err
		}},
		{"template.create", "rigorix.template.create", func(c *Client) error {
			_, err := c.TemplateCreate(ctx, TemplateCreateParams{Name: "t", Plan: map[string]any{}})
			return err
		}},
		{"template.validate", "rigorix.template.validate", func(c *Client) error {
			_, err := c.TemplateValidate(ctx, TemplateValidateParams{Plan: map[string]any{}})
			return err
		}},
		{"auth.login", "rigorix.auth.login", func(c *Client) error {
			_, err := c.AuthLogin(ctx, AuthLoginParams{})
			return err
		}},
		{"auth.status", "rigorix.auth.status", func(c *Client) error {
			_, err := c.AuthStatus(ctx)
			return err
		}},
		{"auth.logout", "rigorix.auth.logout", func(c *Client) error {
			_, err := c.AuthLogout(ctx)
			return err
		}},
		{"usageGuide", "rigorix.usageGuide", func(c *Client) error {
			_, err := c.UsageGuide(ctx)
			return err
		}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			mock := queued(`{"jsonrpc":"2.0","id":1,"result":{}}`)
			if err := tc.call(New(mock)); err != nil {
				t.Fatalf("%s: %v", tc.name, err)
			}
			var request RPCRequest
			if err := json.Unmarshal(mock.Requests[0], &request); err != nil {
				t.Fatal(err)
			}
			if request.Method != tc.method {
				t.Fatalf("method = %s, want %s", request.Method, tc.method)
			}
			if request.JSONRPC != "2.0" {
				t.Fatalf("jsonrpc = %q", request.JSONRPC)
			}
		})
	}
}

func TestVersionAcceptsV1(t *testing.T) {
	version, err := New(queued(versionBody)).Version(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if version.APIVersion != "1.0.0" || version.Name != "rigorix" {
		t.Fatalf("version: %+v", version)
	}
}

func TestVersionRejectsMajor(t *testing.T) {
	body := `{"jsonrpc":"2.0","id":1,"result":{"name":"rigorix","engine_version":"1.7.0","api_version":"v2","schemas":[],"capabilities":[]}}`
	_, err := New(queued(body)).Version(context.Background())
	var mismatch *VersionMismatchError
	if !errors.As(err, &mismatch) {
		t.Fatalf("expected VersionMismatchError, got %v", err)
	}
	if mismatch.Server != "v2" || mismatch.ClientMajor != 1 {
		t.Fatalf("mismatch: %+v", mismatch)
	}
	if !strings.Contains(mismatch.Error(), "v2") {
		t.Fatalf("message must name the advertised major: %s", mismatch.Error())
	}
}

func TestVersionRejectsInvalid(t *testing.T) {
	body := `{"jsonrpc":"2.0","id":1,"result":{"name":"rigorix","engine_version":"1.7.0","api_version":"banana","schemas":[],"capabilities":[]}}`
	_, err := New(queued(body)).Version(context.Background())
	var protocol *ProtocolError
	if !errors.As(err, &protocol) {
		t.Fatalf("expected ProtocolError, got %v", err)
	}
}

func TestIDMismatch(t *testing.T) {
	mock := queued(`{"jsonrpc":"2.0","id":2,"result":{}}`)
	_, err := New(mock).CallRaw(context.Background(), "rigorix.plan", nil)
	var protocol *ProtocolError
	if !errors.As(err, &protocol) {
		t.Fatalf("expected ProtocolError, got %v", err)
	}
}

func TestInvalidResponse(t *testing.T) {
	_, err := New(queued("not-json")).CallRaw(context.Background(), "rigorix.plan", nil)
	var protocol *ProtocolError
	if !errors.As(err, &protocol) {
		t.Fatalf("expected ProtocolError, got %v", err)
	}
}

func TestMissingResult(t *testing.T) {
	_, err := New(queued(`{"jsonrpc":"2.0","id":1}`)).CallRaw(context.Background(), "rigorix.plan", nil)
	var protocol *ProtocolError
	if !errors.As(err, &protocol) {
		t.Fatalf("expected ProtocolError, got %v", err)
	}
}

func TestMockTransportExhausted(t *testing.T) {
	_, err := New(&MockTransport{}).CallRaw(context.Background(), "rigorix.plan", nil)
	var transport *TransportError
	if !errors.As(err, &transport) {
		t.Fatalf("expected TransportError, got %v", err)
	}
}

func TestHTTPTransport(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("x-test") != "1" {
			t.Errorf("missing header, got %q", r.Header.Get("x-test"))
		}
		_, _ = w.Write([]byte(versionBody))
	}))
	defer server.Close()

	client := New(NewHTTPTransport(server.URL, map[string]string{"x-test": "1"}))
	version, err := client.Version(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if version.APIVersion != "1.0.0" {
		t.Fatalf("version: %+v", version)
	}
}

func TestHTTPTransportStatus(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	_, err := New(NewHTTPTransport(server.URL, nil)).Version(context.Background())
	var transport *TransportError
	if !errors.As(err, &transport) {
		t.Fatalf("expected TransportError, got %v", err)
	}
}

func TestCatalogLookup(t *testing.T) {
	if names := MethodNames(); len(names) != len(Methods) {
		t.Fatalf("MethodNames returned %d, want %d", len(names), len(Methods))
	}
	if _, ok := Find("rigorix.plan"); !ok {
		t.Fatal("rigorix.plan must be bound")
	}
	if _, ok := Find("rigorix.nope"); ok {
		t.Fatal("unknown method must not be bound")
	}
}

// TestLiveVersion runs only against a real host.
//
//	RIGORIX_SERVER_URL=http://127.0.0.1:3001/rpc go test ./client -run TestLiveVersion
func TestLiveVersion(t *testing.T) {
	url := os.Getenv("RIGORIX_SERVER_URL")
	if url == "" {
		t.Skip("RIGORIX_SERVER_URL not set")
	}
	version, err := New(NewHTTPTransport(url, nil)).Version(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	major, err := apiMajor(version.APIVersion)
	if err != nil {
		t.Fatal(err)
	}
	if major != ClientAPIMajor {
		t.Fatalf("live server api_version = %q, want major %d", version.APIVersion, ClientAPIMajor)
	}
}
