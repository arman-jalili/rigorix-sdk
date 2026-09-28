package dev.rigorix.sdk.client;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.rigorix.sdk.Canonical;
import dev.rigorix.sdk.Corpus;
import org.junit.jupiter.api.Test;

import java.util.HashSet;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;

class ClientTest {

    @Test
    void catalogDrift() throws Exception {
        JsonNode catalog = Canonical.MAPPER.readTree(Corpus.schema("api/catalog.json"));
        Set<String> frozen = new HashSet<>();
        catalog.get("methods").forEach(method -> frozen.add(method.get("name").asText()));

        Set<String> bound = new HashSet<>(Catalog.names());
        assertEquals(frozen, bound, "client binding must match the frozen catalog exactly");
        Catalog.assertNoRawStepExecution();
    }

    @Test
    void callFraming() throws Exception {
        MockTransport mock = new MockTransport("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"name\":\"rigorix\"}}");
        Client client = new Client(mock);
        JsonNode result = client.callRaw("rigorix.system.version");
        assertEquals("rigorix", result.get("name").asText());

        JsonNode request = Canonical.MAPPER.readTree(mock.requests.get(0));
        assertEquals("2.0", request.get("jsonrpc").asText());
        assertEquals("rigorix.system.version", request.get("method").asText());
    }

    @Test
    void notificationHasNoId() throws Exception {
        MockTransport mock = new MockTransport("{}");
        Client client = new Client(mock);
        ObjectNode params = Canonical.MAPPER.createObjectNode();
        params.put("execution_id", "x");
        client.notify("rigorix.audit.read", params);

        JsonNode request = Canonical.MAPPER.readTree(mock.requests.get(0));
        assertFalse(request.has("id"), "notification must not carry an id");
    }

    @Test
    void rpcErrorSurfaced() {
        MockTransport mock = new MockTransport(
                "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32601,\"message\":\"method not found\"}}");
        Client client = new Client(mock);
        RpcException error = assertThrows(RpcException.class, () -> client.callRaw("rigorix.nope"));
        assertEquals(-32601, error.code());
    }
}
