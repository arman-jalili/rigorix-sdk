package rigorix

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"

	"github.com/arman-jalili/rigorix-sdk/go/internal/corpus"
	"github.com/santhosh-tekuri/jsonschema/v6"
)

// VerifySignature verifies an envelope's HMAC-SHA256 over its canonical bytes.
//
// A `signature: null` envelope is accepted only when `evidence_degraded == true`
// (GAP-M-12); otherwise it fails with ErrUnsignedNotDegraded.
func VerifySignature(envelope any, key string) error {
	obj, err := asObject(envelope)
	if err != nil {
		return err
	}
	raw, present := obj["signature"]
	if !present || raw == nil {
		if degraded, ok := obj["evidence_degraded"].(bool); ok && degraded {
			return nil
		}
		return ErrUnsignedNotDegraded
	}
	signature, ok := raw.(string)
	if !ok {
		return fmt.Errorf("%w: signature is not a string", ErrSignatureMismatch)
	}
	canonical, err := CanonicalBytes(obj)
	if err != nil {
		return err
	}
	mac := hmac.New(sha256.New, []byte(key))
	mac.Write(canonical)
	expected := hex.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(expected), []byte(signature)) {
		return fmt.Errorf("%w: expected %s, got %s", ErrSignatureMismatch, expected, signature)
	}
	return nil
}

// ValidateSchema validates instance against the named contract schema.
func ValidateSchema(schemaRel string, instance any) error {
	schemaText, ok := corpus.Schema(schemaRel)
	if !ok {
		return fmt.Errorf("%w: schema %q not embedded", ErrSchemaViolation, schemaRel)
	}
	doc, err := jsonschema.UnmarshalJSON(strings.NewReader(schemaText))
	if err != nil {
		return err
	}
	url := schemaRel
	if m, ok := doc.(map[string]any); ok {
		if id, ok := m["$id"].(string); ok && id != "" {
			url = id
		}
	}
	compiler := jsonschema.NewCompiler()
	if err := compiler.AddResource(url, doc); err != nil {
		return err
	}
	schema, err := compiler.Compile(url)
	if err != nil {
		return fmt.Errorf("%w: compile %s: %v", ErrSchemaViolation, schemaRel, err)
	}
	value, err := toJSONValue(instance)
	if err != nil {
		return err
	}
	if err := schema.Validate(value); err != nil {
		return fmt.Errorf("%w: %v", ErrSchemaViolation, err)
	}
	return nil
}

// ValidateEnvelope validates an envelope against `envelope.json`.
func ValidateEnvelope(instance any) error { return ValidateSchema("envelope.json", instance) }

func toJSONValue(instance any) (any, error) {
	switch typed := instance.(type) {
	case string:
		return jsonschema.UnmarshalJSON(strings.NewReader(typed))
	case []byte:
		return jsonschema.UnmarshalJSON(bytes.NewReader(typed))
	default:
		return instance, nil
	}
}
