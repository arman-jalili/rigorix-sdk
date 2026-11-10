// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Arman Wolkenstein-Jalili and Rigorix contributors

package eu.rigorix.sdk;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.stream.Stream;

/**
 * Contract-corpus access. The canonical `schemas/**` corpus is packaged under
 * `/rigorix/schemas/**` in the jar (Maven copies the repo-root `schemas/` at
 * build time — the single source of truth, never a committed duplicate).
 */
public final class Corpus {

    private Corpus() {
    }

    /** The contract at {@code relPath} relative to {@code schemas/}. */
    public static String schema(String relPath) {
        return read("/rigorix/schemas/" + relPath);
    }

    /** The fixture at {@code relPath} relative to {@code schemas/fixtures/}. */
    public static String fixture(String relPath) {
        return read("/rigorix/schemas/fixtures/" + relPath);
    }

    static String read(String resource) {
        try (InputStream in = Corpus.class.getResourceAsStream(resource)) {
            if (in == null) {
                throw new VerifyException(VerifyException.Kind.SCHEMA, "contract resource not found: " + resource);
            }
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new VerifyException(VerifyException.Kind.SCHEMA, "read " + resource + ": " + e.getMessage());
        }
    }

    /** Every corpus path relative to {@code schemas/}, sorted (directory runs only). */
    public static List<String> files() {
        URL root = Corpus.class.getResource("/rigorix/schemas");
        if (root == null || !"file".equals(root.getProtocol())) {
            return List.of();
        }
        try {
            Path base = Paths.get(root.toURI());
            try (Stream<Path> walk = Files.walk(base)) {
                return walk.filter(Files::isRegularFile)
                        .map(path -> base.relativize(path).toString().replace(File.separatorChar, '/'))
                        .sorted()
                        .toList();
            }
        } catch (Exception e) {
            return List.of();
        }
    }
}
