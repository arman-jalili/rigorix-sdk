package dev.rigorix.sdk;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class VerifierTest {

    private static final String KEY = "fixture-hmac-key-2026";

    @Test
    void signedEngineFixturesVerifyByteExact() throws Exception {
        int signed = 0;
        for (String path : Corpus.files()) {
            if (!path.startsWith("fixtures/envelope/") || !path.endsWith(".json")) {
                continue;
            }
            String json = Corpus.schema(path);
            JsonNode node = Canonical.MAPPER.readTree(json);
            if (node.get("signature") == null || node.get("signature").isNull()) {
                continue;
            }
            Envelope.verifySignature(json, KEY); // byte-exact canonical form
            Envelope.validateEnvelope(json);
            signed++;
        }
        assertTrue(signed >= 3, "expected >= 3 signed fixtures, found " + signed);
    }

    @Test
    void anchoredFixtureBindsAnchorHead() throws Exception {
        String json = Corpus.fixture("envelope/envelope-anchored-signed.json");
        JsonNode node = Canonical.MAPPER.readTree(json);
        assertEquals("anchored", node.get("history_integrity").asText());
        assertFalse(node.get("anchor_head").isNull());
        assertTrue(node.get("approval_events").size() > 0, "fixture must carry approval_events");

        Envelope.verifySignature(json, KEY);
        Envelope.validateEnvelope(json);

        String canonical = Canonical.canonicalBytes(json);
        assertTrue(canonical.indexOf("\"anchor_head\"") < canonical.indexOf("\"approval_events\""),
                "anchor_head must precede approval_events in the signed bytes");
    }

    @Test
    void tamperingDetected() throws Exception {
        ObjectNode node = (ObjectNode) Canonical.MAPPER.readTree(Corpus.fixture("envelope/envelope-minimal-signed.json"));
        node.put("total_tokens", 999999);
        VerifyException error = assertThrows(VerifyException.class, () -> Envelope.verifySignature(node.toString(), KEY));
        assertEquals(VerifyException.Kind.SIGNATURE_MISMATCH, error.kind());
    }

    @Test
    void unsignedMustBeDegraded() throws Exception {
        ObjectNode node = (ObjectNode) Canonical.MAPPER.readTree(Corpus.fixture("envelope/envelope-unsigned-degraded.json"));
        node.put("evidence_degraded", false);
        VerifyException error = assertThrows(VerifyException.class, () -> Envelope.verifySignature(node.toString(), KEY));
        assertEquals(VerifyException.Kind.UNSIGNED_NOT_DEGRADED, error.kind());
    }

    @Test
    void preconditionFindingsFixtureVerifies() throws Exception {
        String json = Corpus.fixture("envelope/envelope-precondition-signed.json");
        JsonNode findings = Canonical.MAPPER.readTree(json).get("precondition_findings");
        assertEquals(3, findings.size());
        assertEquals("failed", findings.get(0).get("outcome").asText());
        assertEquals(3, findings.get(0).get("exit_code").asInt());
        assertEquals("passed", findings.get(1).get("outcome").asText());
        assertEquals(0, findings.get(1).get("exit_code").asInt());
        assertEquals("error", findings.get(2).get("outcome").asText());
        assertTrue(findings.get(2).get("exit_code").isNull());

        Envelope.verifySignature(json, KEY);
        Envelope.validateEnvelope(json);

        ObjectNode tampered = (ObjectNode) Canonical.MAPPER.readTree(json);
        ((ObjectNode) tampered.get("precondition_findings").get(0))
                .put("inputs_hash", "0".repeat(64));
        assertThrows(VerifyException.class, () -> Envelope.verifySignature(tampered.toString(), KEY));

        String legacy = Corpus.fixture("envelope/envelope-minimal-signed.json");
        assertFalse(legacy.contains("precondition_findings"));
        Envelope.verifySignature(legacy, KEY);
    }
}
