// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

// Package rigorix is an independent (Strategy A) verifier + client for the
// frozen Rigorix contract corpus: envelope HMAC, JSON Schema, ADR-016
// per-producer chains, and Ed25519 anchor artifacts. No rigorix-engine
// dependency; the canonical `schemas/**` corpus is embedded at build time.
package rigorix

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"

	"github.com/arman-jalili/rigorix-sdk/go/internal/corpus"
)

// skipNone mirrors `#[serde(default, skip_serializing_if = "Option::is_none")]`.
var skipNone = map[string]bool{
	"identity":             true,
	"effect_key":           true,
	"producer_id":          true,
	"sequence":             true,
	"prev_hash":            true,
	"history_integrity":    true,
	"history_policy":       true,
	"anchor_head":          true,
	"decision_context_ref": true,
	"payload":              true,
	"sig":                  true,
	"check_digest":         true,
	"authority_digest":     true,
	"check_writable":       true,
	"attribution":          true,
}

// skipEmpty mirrors `skip_serializing_if = "Vec::is_empty"` / map is_empty.
var skipEmpty = map[string]bool{
	"file_paths":               true,
	"scoring_results":          true,
	"approval_events":          true,
	"scope_violations":         true,
	"sequence_policy_findings": true,
	"requirement_findings":     true,
	"precondition_findings":    true,
}

// nestedFields maps a field to the `$defs` struct whose property order applies.
var nestedFields = map[string]string{
	"identity":                 "identityRef",
	"events":                   "executionEventRef",
	"approval_events":          "approvalRecordRef",
	"scope_violations":         "scopeViolationRef",
	"sequence_policy_findings": "sequencePolicyFindingRef",
	"requirement_findings":     "requirementFindingRef",
	"precondition_findings":    "preconditionFindingRef",
	"scoring_results":          "scoringResultRef",
}

var orderCache = map[string][]string{}

// fieldOrder returns `envelope.json`'s property order for the root (defName "")
// or a `$defs` entry — the field order the engine signs (serde declaration order).
func fieldOrder(defName string) ([]string, error) {
	if cached, ok := orderCache[defName]; ok {
		return cached, nil
	}
	raw, ok := corpus.Schema("envelope.json")
	if !ok {
		return nil, fmt.Errorf("embedded envelope.json missing")
	}
	var doc struct {
		Properties json.RawMessage            `json:"properties"`
		Defs       map[string]json.RawMessage `json:"$defs"`
	}
	if err := json.Unmarshal([]byte(raw), &doc); err != nil {
		return nil, err
	}
	props := doc.Properties
	if defName != "" {
		def, ok := doc.Defs[defName]
		if !ok {
			return nil, fmt.Errorf("envelope.json $defs.%s missing", defName)
		}
		var holder struct {
			Properties json.RawMessage `json:"properties"`
		}
		if err := json.Unmarshal(def, &holder); err != nil {
			return nil, err
		}
		props = holder.Properties
	}
	keys, err := objectKeyOrder(props)
	if err != nil {
		return nil, err
	}
	orderCache[defName] = keys
	return keys, nil
}

// objectKeyOrder returns an object's keys in document order.
func objectKeyOrder(raw []byte) ([]string, error) {
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	tok, err := dec.Token()
	if err != nil {
		return nil, err
	}
	if delim, ok := tok.(json.Delim); !ok || delim != '{' {
		return nil, fmt.Errorf("expected a JSON object")
	}
	var keys []string
	for dec.More() {
		key, err := dec.Token()
		if err != nil {
			return nil, err
		}
		keys = append(keys, key.(string))
		var skip json.RawMessage
		if err := dec.Decode(&skip); err != nil {
			return nil, err
		}
	}
	return keys, nil
}

// asObject normalizes an envelope argument (object / JSON string / bytes).
func asObject(value any) (map[string]any, error) {
	switch typed := value.(type) {
	case map[string]any:
		return typed, nil
	case string:
		return decodeObject([]byte(typed))
	case []byte:
		return decodeObject(typed)
	default:
		return nil, fmt.Errorf("expected a JSON object, string, or []byte")
	}
}

func decodeObject(data []byte) (map[string]any, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	var obj map[string]any
	if err := dec.Decode(&obj); err != nil {
		return nil, err
	}
	return obj, nil
}

// CanonicalBytes returns the canonical bytes an envelope's HMAC is computed
// over: compact JSON, `signature` nulled, struct field order from
// `envelope.json`, skip-if-none/empty, map fields sorted, number lexemes
// preserved (`json.Number`).
func CanonicalBytes(envelope any) ([]byte, error) {
	obj, err := asObject(envelope)
	if err != nil {
		return nil, err
	}
	order, err := fieldOrder("")
	if err != nil {
		return nil, err
	}
	var buf bytes.Buffer
	if err := writeObject(&buf, obj, order); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// EnvelopeHash is SHA-256 (hex) of the canonical bytes — the `prev_hash` value.
func EnvelopeHash(envelope any) (string, error) {
	canonical, err := CanonicalBytes(envelope)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(canonical)
	return hex.EncodeToString(sum[:]), nil
}

func canonicalWithOrder(obj map[string]any, order []string) ([]byte, error) {
	var buf bytes.Buffer
	if err := writeObject(&buf, obj, order); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func writeObject(buf *bytes.Buffer, obj map[string]any, fields []string) error {
	buf.WriteByte('{')
	first := true
	for _, field := range fields {
		value, present := obj[field]
		if !present {
			continue
		}
		if value == nil && skipNone[field] {
			continue
		}
		if skipEmpty[field] && isEmptyCollection(value) {
			continue
		}
		if !first {
			buf.WriteByte(',')
		}
		first = false
		writeKey(buf, field)
		if err := writeField(buf, field, value); err != nil {
			return err
		}
	}
	buf.WriteByte('}')
	return nil
}

func writeField(buf *bytes.Buffer, field string, value any) error {
	switch field {
	case "signature", "sig":
		buf.WriteString("null")
		return nil
	case "payload":
		return writeSorted(buf, value)
	case "dimensions":
		return writeStructMap(buf, value, "scoreDimensionRef")
	case "actions":
		return writeHistoryActions(buf, value)
	}
	if defName, ok := nestedFields[field]; ok {
		return writeNested(buf, field, value, defName)
	}
	return writeScalar(buf, value)
}

func writeNested(buf *bytes.Buffer, field string, value any, defName string) error {
	if field == "scoring_results" {
		return writeStructMap(buf, value, defName)
	}
	order, err := fieldOrder(defName)
	if err != nil {
		return err
	}
	if arr, ok := value.([]any); ok {
		buf.WriteByte('[')
		for i, item := range arr {
			if i > 0 {
				buf.WriteByte(',')
			}
			obj, ok := item.(map[string]any)
			if !ok {
				return fmt.Errorf("%s[%d] is not an object", field, i)
			}
			if err := writeObject(buf, obj, order); err != nil {
				return err
			}
		}
		buf.WriteByte(']')
		return nil
	}
	obj, ok := value.(map[string]any)
	if !ok {
		return fmt.Errorf("%s is not an object", field)
	}
	return writeObject(buf, obj, order)
}

// writeStructMap writes a map of structs with sorted keys (deterministic, like
// serde's sorted map serialization).
func writeStructMap(buf *bytes.Buffer, value any, defName string) error {
	m, ok := value.(map[string]any)
	if !ok {
		return fmt.Errorf("expected an object map for %s", defName)
	}
	order, err := fieldOrder(defName)
	if err != nil {
		return err
	}
	keys := sortedKeys(m)
	buf.WriteByte('{')
	for i, key := range keys {
		if i > 0 {
			buf.WriteByte(',')
		}
		writeKey(buf, key)
		entry, ok := m[key].(map[string]any)
		if !ok {
			return fmt.Errorf("%s entry %q is not an object", defName, key)
		}
		if err := writeObject(buf, entry, order); err != nil {
			return err
		}
	}
	buf.WriteByte('}')
	return nil
}

func writeHistoryActions(buf *bytes.Buffer, value any) error {
	arr, ok := value.([]any)
	if !ok {
		return fmt.Errorf("actions is not an array")
	}
	buf.WriteByte('[')
	for i, item := range arr {
		if i > 0 {
			buf.WriteByte(',')
		}
		obj, ok := item.(map[string]any)
		if !ok {
			return fmt.Errorf("actions[%d] is not an object", i)
		}
		buf.WriteByte('{')
		first := true
		for _, field := range []string{"node", "principal", "at", "effect_key"} {
			v, present := obj[field]
			if !present || (field == "effect_key" && v == nil) {
				continue
			}
			if !first {
				buf.WriteByte(',')
			}
			first = false
			writeKey(buf, field)
			if err := writeScalar(buf, v); err != nil {
				return err
			}
		}
		buf.WriteByte('}')
	}
	buf.WriteByte(']')
	return nil
}

// writeSorted writes a `serde_json::Value` with every object key sorted.
func writeSorted(buf *bytes.Buffer, value any) error {
	switch typed := value.(type) {
	case map[string]any:
		buf.WriteByte('{')
		for i, key := range sortedKeys(typed) {
			if i > 0 {
				buf.WriteByte(',')
			}
			writeKey(buf, key)
			if err := writeSorted(buf, typed[key]); err != nil {
				return err
			}
		}
		buf.WriteByte('}')
		return nil
	case []any:
		buf.WriteByte('[')
		for i, item := range typed {
			if i > 0 {
				buf.WriteByte(',')
			}
			if err := writeSorted(buf, item); err != nil {
				return err
			}
		}
		buf.WriteByte(']')
		return nil
	default:
		return writeScalar(buf, value)
	}
}

func writeScalar(buf *bytes.Buffer, value any) error {
	switch typed := value.(type) {
	case nil:
		buf.WriteString("null")
	case bool:
		if typed {
			buf.WriteString("true")
		} else {
			buf.WriteString("false")
		}
	case string:
		encoded, _ := json.Marshal(typed)
		buf.Write(encoded)
	case json.Number:
		buf.WriteString(typed.String())
	case float64:
		encoded, _ := json.Marshal(typed)
		buf.Write(encoded)
	case []any:
		buf.WriteByte('[')
		for i, item := range typed {
			if i > 0 {
				buf.WriteByte(',')
			}
			if err := writeScalar(buf, item); err != nil {
				return err
			}
		}
		buf.WriteByte(']')
	default:
		encoded, err := json.Marshal(typed)
		if err != nil {
			return err
		}
		buf.Write(encoded)
	}
	return nil
}

func writeKey(buf *bytes.Buffer, key string) {
	encoded, _ := json.Marshal(key)
	buf.Write(encoded)
	buf.WriteByte(':')
}

func isEmptyCollection(value any) bool {
	switch typed := value.(type) {
	case []any:
		return len(typed) == 0
	case map[string]any:
		return len(typed) == 0
	default:
		return false
	}
}

func sortedKeys(m map[string]any) []string {
	keys := make([]string, 0, len(m))
	for key := range m {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}
