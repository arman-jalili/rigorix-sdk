// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package eu.rigorix.sdk;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.json.JsonMapper;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Canonical envelope bytes — byte-exact with the rigorix-oss engine and the
 * other verifiers.
 *
 * <p>Compact JSON, {@code signature} nulled, struct field order read from
 * {@code schemas/envelope.json}, {@code skip_serializing_if} handling, map
 * fields sorted, and number lexemes preserved (exact {@code BigDecimal}).
 */
public final class Canonical {

    public static final ObjectMapper MAPPER = JsonMapper.builder()
            .enable(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)
            .nodeFactory(JsonNodeFactory.withExactBigDecimals(true))
            .build();

    private static final Set<String> SKIP_NONE = Set.of(
            "identity", "effect_key", "producer_id", "sequence", "prev_hash",
            "history_integrity", "history_policy", "anchor_head",
            "decision_context_ref", "scope_check", "payload", "sig",
            "check_digest", "authority_digest", "check_writable", "attribution");

    private static final Set<String> SKIP_EMPTY = Set.of(
            "file_paths", "scoring_results", "approval_events",
            "scope_violations", "sequence_policy_findings", "requirement_findings", "precondition_findings");

    private static final Map<String, String> NESTED = Map.ofEntries(
            Map.entry("identity", "identityRef"),
            Map.entry("events", "executionEventRef"),
            Map.entry("approval_events", "approvalRecordRef"),
            Map.entry("scope_violations", "scopeViolationRef"),
            Map.entry("sequence_policy_findings", "sequencePolicyFindingRef"),
            Map.entry("requirement_findings", "requirementFindingRef"),
            Map.entry("precondition_findings", "preconditionFindingRef"),
            Map.entry("scoring_results", "scoringResultRef"));

    private static final Map<String, List<String>> ORDER_CACHE = new HashMap<>();

    private Canonical() {
    }

    /** Property order for the root envelope ({@code defName == ""}) or a `$defs` entry. */
    static synchronized List<String> fieldOrder(String defName) {
        List<String> cached = ORDER_CACHE.get(defName);
        if (cached != null) {
            return cached;
        }
        try {
            ObjectNode doc = (ObjectNode) MAPPER.readTree(Corpus.schema("envelope.json"));
            JsonNode properties = defName.isEmpty()
                    ? doc.get("properties")
                    : doc.get("$defs").get(defName).get("properties");
            List<String> keys = new ArrayList<>();
            properties.fieldNames().forEachRemaining(keys::add);
            ORDER_CACHE.put(defName, keys);
            return keys;
        } catch (Exception e) {
            throw new VerifyException(VerifyException.Kind.SCHEMA, "envelope.json field order: " + e.getMessage());
        }
    }

    /** The canonical bytes an envelope's HMAC is computed over. */
    public static String canonicalBytes(String json) {
        try {
            return withOrder((ObjectNode) MAPPER.readTree(json), fieldOrder(""));
        } catch (VerifyException e) {
            throw e;
        } catch (Exception e) {
            throw new VerifyException(VerifyException.Kind.SCHEMA, "parse envelope: " + e.getMessage());
        }
    }

    /** SHA-256 (hex) of the canonical bytes — the {@code prev_hash} value. */
    public static String envelopeHash(String json) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(canonicalBytes(json).getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    static String withOrder(ObjectNode obj, List<String> order) {
        StringBuilder sb = new StringBuilder();
        sb.append('{');
        boolean first = true;
        for (String field : order) {
            JsonNode value = obj.get(field);
            if (value == null) {
                continue;
            }
            if (value.isNull() && SKIP_NONE.contains(field)) {
                continue;
            }
            if (SKIP_EMPTY.contains(field) && isEmpty(value)) {
                continue;
            }
            if (!first) {
                sb.append(',');
            }
            first = false;
            appendKey(sb, field);
            appendField(sb, field, value);
        }
        sb.append('}');
        return sb.toString();
    }

    private static void appendField(StringBuilder sb, String field, JsonNode value) {
        switch (field) {
            case "signature":
            case "sig":
                sb.append("null");
                return;
            case "payload":
                appendSorted(sb, value);
                return;
            case "dimensions":
                appendStructMap(sb, value, "scoreDimensionRef");
                return;
            case "actions":
                appendHistoryActions(sb, value);
                return;
            default:
                break;
        }
        String defName = NESTED.get(field);
        if (defName != null) {
            appendNested(sb, field, value, defName);
            return;
        }
        appendScalar(sb, value);
    }

    private static void appendNested(StringBuilder sb, String field, JsonNode value, String defName) {
        if (field.equals("scoring_results")) {
            appendStructMap(sb, value, defName);
            return;
        }
        List<String> order = fieldOrder(defName);
        if (value.isArray()) {
            sb.append('[');
            for (int i = 0; i < value.size(); i++) {
                if (i > 0) {
                    sb.append(',');
                }
                sb.append(withOrder((ObjectNode) value.get(i), order));
            }
            sb.append(']');
        } else {
            sb.append(withOrder((ObjectNode) value, order));
        }
    }

    private static void appendStructMap(StringBuilder sb, JsonNode value, String defName) {
        List<String> order = fieldOrder(defName);
        List<String> keys = new ArrayList<>();
        value.fieldNames().forEachRemaining(keys::add);
        Collections.sort(keys);
        sb.append('{');
        for (int i = 0; i < keys.size(); i++) {
            if (i > 0) {
                sb.append(',');
            }
            appendKey(sb, keys.get(i));
            sb.append(withOrder((ObjectNode) value.get(keys.get(i)), order));
        }
        sb.append('}');
    }

    private static void appendHistoryActions(StringBuilder sb, JsonNode value) {
        List<String> order = List.of("node", "principal", "at", "effect_key");
        sb.append('[');
        for (int i = 0; i < value.size(); i++) {
            if (i > 0) {
                sb.append(',');
            }
            ObjectNode action = (ObjectNode) value.get(i);
            sb.append('{');
            boolean first = true;
            for (String field : order) {
                JsonNode fieldValue = action.get(field);
                if (fieldValue == null || (field.equals("effect_key") && fieldValue.isNull())) {
                    continue;
                }
                if (!first) {
                    sb.append(',');
                }
                first = false;
                appendKey(sb, field);
                appendScalar(sb, fieldValue);
            }
            sb.append('}');
        }
        sb.append(']');
    }

    /** Recursively sorted (`serde_json::Value` payload map). */
    private static void appendSorted(StringBuilder sb, JsonNode value) {
        if (value.isObject()) {
            List<String> keys = new ArrayList<>();
            value.fieldNames().forEachRemaining(keys::add);
            Collections.sort(keys);
            sb.append('{');
            for (int i = 0; i < keys.size(); i++) {
                if (i > 0) {
                    sb.append(',');
                }
                appendKey(sb, keys.get(i));
                appendSorted(sb, value.get(keys.get(i)));
            }
            sb.append('}');
        } else if (value.isArray()) {
            sb.append('[');
            for (int i = 0; i < value.size(); i++) {
                if (i > 0) {
                    sb.append(',');
                }
                appendSorted(sb, value.get(i));
            }
            sb.append(']');
        } else {
            appendScalar(sb, value);
        }
    }

    private static void appendScalar(StringBuilder sb, JsonNode value) {
        if (value.isNull()) {
            sb.append("null");
        } else if (value.isTextual()) {
            appendJsonString(sb, value.textValue());
        } else if (value.isNumber()) {
            sb.append(value.asText());
        } else if (value.isBoolean()) {
            sb.append(value.booleanValue() ? "true" : "false");
        } else if (value.isArray()) {
            sb.append('[');
            for (int i = 0; i < value.size(); i++) {
                if (i > 0) {
                    sb.append(',');
                }
                appendScalar(sb, value.get(i));
            }
            sb.append(']');
        } else {
            sb.append(value);
        }
    }

    private static void appendKey(StringBuilder sb, String key) {
        appendJsonString(sb, key);
        sb.append(':');
    }

    private static void appendJsonString(StringBuilder sb, String text) {
        try {
            sb.append(MAPPER.writeValueAsString(text));
        } catch (JsonProcessingException e) {
            throw new VerifyException(VerifyException.Kind.SCHEMA, "encode string: " + e.getMessage());
        }
    }

    private static boolean isEmpty(JsonNode value) {
        return (value.isArray() && value.isEmpty()) || (value.isObject() && value.isEmpty());
    }
}
