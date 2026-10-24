package eu.rigorix.sdk;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class ChainAnchorTest {

    static final String ANCHOR_PUBLIC_KEY = "ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c";

    private static List<JsonNode> chain(String name) throws Exception {
        ArrayNode array = (ArrayNode) Canonical.MAPPER.readTree(Corpus.fixture("integrity/" + name));
        List<JsonNode> out = new ArrayList<>();
        array.forEach(out::add);
        return out;
    }

    private static JsonNode object(String rel) throws Exception {
        return Canonical.MAPPER.readTree(Corpus.fixture(rel));
    }

    @Test
    void validChainVerifies() throws Exception {
        Chain.verifyChain(chain("chain.json"));
    }

    @Test
    void brokenChainRejected() throws Exception {
        assertThrows(VerifyException.class, () -> Chain.verifyChain(chain("broken-chain.json")));
    }

    @Test
    void alteredPredecessorRejected() throws Exception {
        List<JsonNode> envelopes = chain("chain.json");
        ((ObjectNode) envelopes.get(envelopes.size() - 1)).put("prev_hash", "0".repeat(64));
        assertThrows(VerifyException.class, () -> Chain.verifyChain(envelopes));
    }

    @Test
    void duplicateSequenceRejected() throws Exception {
        List<JsonNode> envelopes = chain("chain.json");
        ((ObjectNode) envelopes.get(envelopes.size() - 1))
                .put("sequence", envelopes.get(envelopes.size() - 2).get("sequence").asInt());
        assertThrows(VerifyException.class, () -> Chain.verifyChain(envelopes));
    }

    @Test
    void checkpointCoversGap() throws Exception {
        List<JsonNode> broken = chain("broken-chain.json");
        JsonNode checkpoint = object("integrity/compaction-checkpoint.json");
        assertThrows(VerifyException.class, () -> Chain.verifyChain(broken));
        Chain.verifyChainWithCheckpoints(broken, List.of(checkpoint), ANCHOR_PUBLIC_KEY);
    }

    @Test
    void forgedCheckpointRejected() throws Exception {
        List<JsonNode> broken = chain("broken-chain.json");
        ObjectNode forged = (ObjectNode) object("integrity/compaction-checkpoint.json");
        forged.put("new_head", "0".repeat(64));
        VerifyException error = assertThrows(VerifyException.class,
                () -> Chain.verifyChainWithCheckpoints(broken, List.of(forged), ANCHOR_PUBLIC_KEY));
        assertEquals(VerifyException.Kind.ANCHOR_SIGNATURE, error.kind());
    }

    @Test
    void anchorArtifactsVerify() throws Exception {
        Anchor.verifyLedgerReceipt(object("integrity/ledger-receipt.json"), ANCHOR_PUBLIC_KEY);
        Anchor.verifyHistorySlice(object("integrity/history-slice.json"), ANCHOR_PUBLIC_KEY);
        Anchor.verifyCompactionCheckpoint(object("integrity/compaction-checkpoint.json"), ANCHOR_PUBLIC_KEY);
    }

    @Test
    void historySliceTamperRejected() throws Exception {
        ObjectNode slice = (ObjectNode) object("integrity/history-slice.json");
        ((ObjectNode) slice.get("actions").get(0)).put("node", "forged_node");
        assertThrows(VerifyException.class, () -> Anchor.verifyHistorySlice(slice, ANCHOR_PUBLIC_KEY));
    }
}
