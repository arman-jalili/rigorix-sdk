// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package eu.rigorix.sdk.client;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import eu.rigorix.sdk.Canonical;

import java.io.IOException;

/** A typed JSON-RPC 2.0 client over the frozen {@code rigorix.*} catalog. */
public final class Client {

    /** The native API major this client targets ({@code catalog.json} `apiVersion`). */
    public static final int CLIENT_API_MAJOR = 1;
    /** The full native API version this client was built against. */
    public static final String CLIENT_API_VERSION = "1.0.0";

    private final Transport transport;
    private int nextId = 1;

    public Client(Transport transport) {
        this.transport = transport;
    }

    /** Call a method and return the raw {@code result}. */
    public JsonNode callRaw(String method, JsonNode params) throws IOException {
        JsonNode response = Canonical.MAPPER.readTree(transport.post(request(method, params, true).toString()));
        JsonNode error = response.get("error");
        if (error != null && !error.isNull()) {
            throw new RpcException(error.path("code").asInt(), error.path("message").asText());
        }
        JsonNode result = response.get("result");
        if (result == null) {
            throw new IllegalStateException("response has neither `result` nor `error`");
        }
        return result;
    }

    /** Send a notification (no {@code id}; no response expected). */
    public void notify(String method, JsonNode params) throws IOException {
        transport.post(request(method, params, false).toString());
    }

    /** Call a method with no params. */
    public JsonNode callRaw(String method) throws IOException {
        return callRaw(method, Canonical.MAPPER.createObjectNode());
    }

    /** Call {@code rigorix.system.version}. */
    public JsonNode version() throws IOException {
        return callRaw("rigorix.system.version");
    }

    /** Call a batch (one JSON array) and return the raw response array. */
    public ArrayNode batchRaw(java.util.List<BatchCall> calls) throws IOException {
        ArrayNode requests = Canonical.MAPPER.createArrayNode();
        for (BatchCall call : calls) {
            requests.add(request(call.method(), call.params(), true));
        }
        JsonNode response = Canonical.MAPPER.readTree(transport.post(requests.toString()));
        if (!response.isArray()) {
            throw new IllegalStateException("batch response is not an array");
        }
        return (ArrayNode) response;
    }

    private ObjectNode request(String method, JsonNode params, boolean withId) {
        ObjectNode request = Canonical.MAPPER.createObjectNode();
        request.put("jsonrpc", "2.0");
        request.put("method", method);
        if (params != null) {
            request.set("params", params);
        }
        if (withId) {
            request.put("id", nextId++);
        }
        return request;
    }

    /** One raw call in a batch. */
    public record BatchCall(String method, JsonNode params) {
        public BatchCall(String method) {
            this(method, Canonical.MAPPER.createObjectNode());
        }
    }
}
