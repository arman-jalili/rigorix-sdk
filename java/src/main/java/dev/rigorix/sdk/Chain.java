package dev.rigorix.sdk;

import com.fasterxml.jackson.databind.JsonNode;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

/** ADR-016 local per-producer chain verification. */
public final class Chain {

    private Chain() {
    }

    /** Verify the strict local chain (no gap is accepted). */
    public static void verifyChain(List<JsonNode> envelopes) {
        verifyChainWithCheckpoints(envelopes, List.of(), "");
    }

    /** Verify the chain, accepting a gap iff a valid signed checkpoint covers it. */
    public static void verifyChainWithCheckpoints(List<JsonNode> envelopes, List<JsonNode> checkpoints, String anchorPublicKeyHex) {
        for (JsonNode checkpoint : checkpoints) {
            Anchor.verifyCompactionCheckpoint(checkpoint, anchorPublicKeyHex);
        }

        Map<String, List<JsonNode>> producers = new TreeMap<>();
        for (JsonNode envelope : envelopes) {
            JsonNode producer = envelope.get("producer_id");
            JsonNode sequence = envelope.get("sequence");
            if (producer != null && !producer.isNull() && sequence != null && !sequence.isNull()) {
                producers.computeIfAbsent(producer.asText(), ignored -> new ArrayList<>()).add(envelope);
            }
        }

        for (Map.Entry<String, List<JsonNode>> entry : producers.entrySet()) {
            String producer = entry.getKey();
            List<JsonNode> chain = entry.getValue();
            chain.sort(Comparator.comparingInt(node -> node.get("sequence").asInt()));

            int base = chain.get(0).get("sequence").asInt();
            if (base != 0) {
                throw broken("producer '" + producer + "': chain starts at sequence " + base
                        + ", not genesis 0 — the earliest envelope(s) were deleted");
            }
            JsonNode genesisPrev = chain.get(0).get("prev_hash");
            if (genesisPrev != null && !genesisPrev.isNull()) {
                throw broken("producer '" + producer + "': genesis envelope carries a prev_hash");
            }

            for (int i = 0; i + 1 < chain.size(); i++) {
                JsonNode prev = chain.get(i);
                JsonNode next = chain.get(i + 1);
                int prevSequence = prev.get("sequence").asInt();
                int nextSequence = next.get("sequence").asInt();
                if (nextSequence <= prevSequence) {
                    throw broken("producer '" + producer + "': sequence not strictly increasing ("
                            + prevSequence + " -> " + nextSequence + ")");
                }
                String prevHash = Canonical.envelopeHash(prev.toString());
                if (nextSequence == prevSequence + 1) {
                    if (!text(next, "prev_hash").equals(prevHash)) {
                        throw broken("producer '" + producer + "': prev_hash mismatch at sequence " + nextSequence);
                    }
                    continue;
                }
                String link = text(next, "prev_hash");
                if (link.isEmpty()) {
                    throw broken("producer '" + producer + "': missing prev_hash after gap at sequence " + nextSequence);
                }
                boolean covered = false;
                for (JsonNode checkpoint : checkpoints) {
                    if (intOf(checkpoint, "sequence_from") == prevSequence + 1
                            && intOf(checkpoint, "sequence_to") == nextSequence - 1
                            && text(checkpoint, "prior_head").equals(prevHash)
                            && text(checkpoint, "new_head").equals(link)) {
                        covered = true;
                        break;
                    }
                }
                if (!covered) {
                    throw broken("producer '" + producer + "': uncovered gap sequences "
                            + (prevSequence + 1) + "..=" + (nextSequence - 1));
                }
            }
        }
    }

    private static VerifyException broken(String detail) {
        return new VerifyException(VerifyException.Kind.CHAIN_BROKEN, detail);
    }

    private static String text(JsonNode node, String field) {
        JsonNode value = node.get(field);
        return value == null || value.isNull() ? "" : value.asText();
    }

    private static int intOf(JsonNode node, String field) {
        JsonNode value = node.get(field);
        return value == null || value.isNull() ? -1 : value.asInt(-1);
    }
}
