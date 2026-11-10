// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package eu.rigorix.sdk.client;

import java.io.IOException;

/** Transport seam — the client depends on no HTTP framework. */
public interface Transport {

    /** POST a JSON-RPC body and return the raw response body. */
    String post(String body) throws IOException;
}
