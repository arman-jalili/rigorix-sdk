// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package eu.rigorix.sdk.client;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Map;

/** A {@link java.net.http.HttpClient}-based transport. */
public final class HttpTransport implements Transport {

    private final HttpClient client = HttpClient.newHttpClient();
    private final URI uri;
    private final Map<String, String> headers;

    public HttpTransport(String url, Map<String, String> headers) {
        this.uri = URI.create(url);
        this.headers = headers == null ? Map.of() : headers;
    }

    @Override
    public String post(String body) throws IOException {
        HttpRequest.Builder builder = HttpRequest.newBuilder(uri)
                .header("content-type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body));
        headers.forEach(builder::header);
        try {
            HttpResponse<String> response = client.send(builder.build(), HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                throw new IOException("transport: HTTP " + response.statusCode());
            }
            return response.body();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IOException("interrupted", e);
        }
    }
}
