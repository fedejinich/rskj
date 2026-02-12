/*
 * This file is part of RskJ
 * Copyright (C) 2026 RSK Labs Ltd.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
package co.rsk.trie.engine.rust.diagnostics;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;

class JsonlTrieDifferentialRecorderTest {

    private static final ObjectMapper JSON_MAPPER = new ObjectMapper();

    @TempDir
    Path tempDir;

    @Test
    void writesJsonlEventsWithDeterministicStepIndex() throws IOException {
        Path outputFile = tempDir.resolve("corpus.jsonl");
        try (JsonlTrieDifferentialRecorder recorder = new JsonlTrieDifferentialRecorder(outputFile)) {
            recorder.recordOperation(
                    "put",
                    "SPEC-TRIE-PUT-SPLIT-COALESCE-001",
                    "trie",
                    "mutation",
                    "next",
                    new byte[]{0x01},
                    new byte[]{0x02},
                    1,
                    null,
                    null,
                    new byte[]{0x0a},
                    new byte[]{0x0b},
                    null
            );
            recorder.recordOperation(
                    "get",
                    "SPEC-TRIE-GET-FIND-001",
                    "trie",
                    "read",
                    "next",
                    new byte[]{0x01},
                    null,
                    null,
                    null,
                    null,
                    new byte[]{0x0a},
                    new byte[]{0x0b},
                    "simulated mismatch"
            );
        }

        var lines = Files.readAllLines(outputFile);
        assertEquals(2, lines.size());

        Map<?, ?> first = JSON_MAPPER.readValue(lines.get(0), Map.class);
        Map<?, ?> second = JSON_MAPPER.readValue(lines.get(1), Map.class);

        assertEquals(0, ((Number) first.get("stepIndex")).intValue());
        assertEquals("put", first.get("op"));
        assertEquals("SPEC-TRIE-PUT-SPLIT-COALESCE-001", first.get("specId"));
        assertEquals("trie", first.get("specClass"));
        assertEquals("mutation", first.get("phase"));
        assertEquals("next", first.get("engineImpl"));
        assertEquals(1, ((Number) first.get("valueLen")).intValue());

        assertEquals(1, ((Number) second.get("stepIndex")).intValue());
        assertEquals("simulated mismatch", second.get("mismatchMessage"));
        assertEquals("read", second.get("phase"));
    }
}
