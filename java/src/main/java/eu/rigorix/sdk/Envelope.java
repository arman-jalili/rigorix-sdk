// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package eu.rigorix.sdk;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.networknt.schema.JsonSchema;
import com.networknt.schema.JsonSchemaFactory;
import com.networknt.schema.SpecVersion;
import com.networknt.schema.ValidationMessage;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.Set;

/** Envelope HMAC verification + JSON Schema conformance. */
public final class Envelope {

    private Envelope() {
    }

    /** Verify an envelope's HMAC-SHA256 over its canonical bytes (GAP-M-12 aware). */
    public static void verifySignature(String json, String key) {
        ObjectNode envelope;
        try {
            envelope = (ObjectNode) Canonical.MAPPER.readTree(json);
        } catch (Exception e) {
            throw new VerifyException(VerifyException.Kind.SCHEMA, "parse envelope: " + e.getMessage());
        }
        JsonNode signature = envelope.get("signature");
        if (signature == null || signature.isNull()) {
            JsonNode degraded = envelope.get("evidence_degraded");
            if (degraded != null && degraded.asBoolean(false)) {
                return;
            }
            throw new VerifyException(VerifyException.Kind.UNSIGNED_NOT_DEGRADED,
                    "unsigned envelope without evidence_degraded=true (GAP-M-12 violation)");
        }
        String expected = hmacHex(key, Canonical.canonicalBytes(json));
        if (!MessageDigest.isEqual(
                expected.getBytes(StandardCharsets.UTF_8),
                signature.asText().getBytes(StandardCharsets.UTF_8))) {
            throw new VerifyException(VerifyException.Kind.SIGNATURE_MISMATCH,
                    "signature mismatch: expected " + expected + ", got " + signature.asText());
        }
    }

    /** Validate an envelope against {@code envelope.json}. */
    public static void validateEnvelope(String json) {
        validateSchema("envelope.json", json);
    }

    /** Validate {@code json} against the named contract schema. */
    public static void validateSchema(String relPath, String json) {
        try {
            JsonSchemaFactory factory = JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V202012);
            JsonSchema schema = factory.getSchema(Canonical.MAPPER.readTree(Corpus.schema(relPath)));
            Set<ValidationMessage> errors = schema.validate(Canonical.MAPPER.readTree(json));
            if (!errors.isEmpty()) {
                throw new VerifyException(VerifyException.Kind.SCHEMA,
                        String.join("; ", errors.stream().map(ValidationMessage::getMessage).toList()));
            }
        } catch (VerifyException e) {
            throw e;
        } catch (Exception e) {
            throw new VerifyException(VerifyException.Kind.SCHEMA, "schema " + relPath + ": " + e.getMessage());
        }
    }

    static String hmacHex(String key, String canonical) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return HexFormat.of().formatHex(mac.doFinal(canonical.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
