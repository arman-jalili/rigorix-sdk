package dev.rigorix.sdk.client;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;

/** A test transport that records requests and replays queued responses. */
public final class MockTransport implements Transport {

    /** Every request body posted, in order. */
    public final List<String> requests = new ArrayList<>();

    private final Deque<String> responses = new ArrayDeque<>();

    public MockTransport(String... responses) {
        for (String response : responses) {
            this.responses.add(response);
        }
    }

    @Override
    public String post(String body) {
        requests.add(body);
        if (responses.isEmpty()) {
            throw new IllegalStateException("mock transport: no queued response");
        }
        return responses.poll();
    }
}
