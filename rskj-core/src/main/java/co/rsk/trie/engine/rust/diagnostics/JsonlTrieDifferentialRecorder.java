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
import org.ethereum.util.ByteUtil;

import javax.annotation.Nullable;
import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;

public final class JsonlTrieDifferentialRecorder implements TrieDifferentialRecorder {
    private static final ObjectMapper JSON_MAPPER = new ObjectMapper();

    private final BufferedWriter writer;
    private final AtomicLong stepIndex = new AtomicLong(0L);

    public JsonlTrieDifferentialRecorder(Path outputFile) {
        try {
            Path parent = outputFile.getParent();
            if (parent != null) {
                Files.createDirectories(parent);
            }
            this.writer = Files.newBufferedWriter(
                    outputFile,
                    StandardCharsets.UTF_8
            );
        } catch (IOException e) {
            throw new IllegalStateException("Could not initialize trie differential recorder", e);
        }
    }

    @Override
    public boolean isEnabled() {
        return true;
    }

    @Override
    public synchronized void recordOperation(
            String op,
            @Nullable byte[] key,
            @Nullable byte[] value,
            @Nullable Integer valueLength,
            @Nullable byte[] valueHash,
            @Nullable Integer size,
            @Nullable byte[] javaRootAfter,
            @Nullable byte[] rustRootAfter,
            @Nullable String mismatchMessage) {
        try {
            Map<String, Object> event = new LinkedHashMap<>();
            event.put("stepIndex", stepIndex.getAndIncrement());
            event.put("op", op);
            event.put("keyHex", nullableHex(key));
            event.put("valueHex", nullableHex(value));
            event.put("valueLen", valueLength != null ? valueLength : (value == null ? null : value.length));
            event.put("valueHash", nullableHex(valueHash));
            event.put("size", size);
            event.put("javaRootAfter", nullableHex(javaRootAfter));
            event.put("rustRootAfter", nullableHex(rustRootAfter));
            event.put("mismatchMessage", mismatchMessage);

            writer.write(JSON_MAPPER.writeValueAsString(event));
            writer.newLine();
            writer.flush();
        } catch (IOException e) {
            throw new IllegalStateException("Could not write trie differential JSONL event", e);
        }
    }

    @Override
    public synchronized void close() {
        try {
            writer.close();
        } catch (IOException e) {
            throw new IllegalStateException("Could not close trie differential recorder", e);
        }
    }

    @Nullable
    private static String nullableHex(@Nullable byte[] value) {
        return value == null ? null : ByteUtil.toHexString(value);
    }
}
