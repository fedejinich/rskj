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

package co.rsk.jmh.trie.core;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.bouncycastle.util.encoders.Hex;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class TrieCoreWorkloadCorpus {

    public static final String CORE_CORPUS_PATH_PROPERTY = "unitrie.jmh.coreCorpusPath";
    public static final String CORE_CORPUS_PATH_ENV = "UNITRIE_JMH_CORE_CORPUS_PATH";

    private static final ObjectMapper JSON_MAPPER = new ObjectMapper();
    private static final String DEFAULT_CORPUS_RELATIVE_PATH = "benchmarks/unitrie-corpus/workloads-v1.json";

    private final String version;
    private final Map<String, Workload> workloadsByName;

    private TrieCoreWorkloadCorpus(String version, Map<String, Workload> workloadsByName) {
        this.version = version;
        this.workloadsByName = Collections.unmodifiableMap(new LinkedHashMap<>(workloadsByName));
    }

    public static TrieCoreWorkloadCorpus loadDefault() {
        Path path = resolveCorpusPath();
        if (!Files.exists(path)) {
            throw new IllegalStateException("Core trie workload corpus not found at " + path.toAbsolutePath());
        }

        try {
            RawCorpus rawCorpus = JSON_MAPPER.readValue(path.toFile(), RawCorpus.class);
            if (rawCorpus.workloads == null || rawCorpus.workloads.isEmpty()) {
                throw new IllegalStateException("Core trie workload corpus has no workloads: " + path.toAbsolutePath());
            }

            Map<String, Workload> workloads = new LinkedHashMap<>();
            for (RawWorkload rawWorkload : rawCorpus.workloads) {
                Workload workload = Workload.fromRaw(rawWorkload);
                if (workloads.putIfAbsent(workload.name(), workload) != null) {
                    throw new IllegalStateException("Duplicated workload name in corpus: " + workload.name());
                }
            }

            String version = rawCorpus.version == null || rawCorpus.version.isBlank()
                    ? "unknown"
                    : rawCorpus.version;
            return new TrieCoreWorkloadCorpus(version, workloads);
        } catch (IOException e) {
            throw new IllegalStateException("Could not load core trie workload corpus from " + path.toAbsolutePath(), e);
        }
    }

    public String version() {
        return version;
    }

    public List<String> workloadNames() {
        return new ArrayList<>(workloadsByName.keySet());
    }

    public Workload workload(String name) {
        Workload workload = workloadsByName.get(name);
        if (workload == null) {
            throw new IllegalArgumentException("Unknown core workload: " + name);
        }

        return workload;
    }

    private static Path resolveCorpusPath() {
        String configured = System.getProperty(CORE_CORPUS_PATH_PROPERTY);
        if (configured == null || configured.isBlank()) {
            configured = System.getenv(CORE_CORPUS_PATH_ENV);
        }

        if (configured != null && !configured.isBlank()) {
            return Paths.get(configured).toAbsolutePath().normalize();
        }

        Path cwd = Paths.get(System.getProperty("user.dir", ".")).toAbsolutePath().normalize();
        Path[] candidates = new Path[] {
                cwd.resolve(DEFAULT_CORPUS_RELATIVE_PATH),
                cwd.getParent() == null
                        ? cwd.resolve(DEFAULT_CORPUS_RELATIVE_PATH)
                        : cwd.getParent().resolve(DEFAULT_CORPUS_RELATIVE_PATH)
        };

        for (Path candidate : candidates) {
            if (Files.exists(candidate)) {
                return candidate;
            }
        }

        return candidates[0];
    }

    public enum OperationType {
        PUT,
        GET,
        DELETE,
        DELETE_RECURSIVE,
        GET_VALUE_LENGTH,
        GET_VALUE_HASH,
        COLLECT_KEYS,
        SAVE,
        SAVE_RELOAD,
        ROOT_HASH;

        static OperationType fromConfig(String value) {
            if (value == null || value.isBlank()) {
                throw new IllegalArgumentException("Operation type must not be empty");
            }

            String normalized = value.trim().toLowerCase(Locale.ROOT)
                    .replace("-", "")
                    .replace("_", "");

            return switch (normalized) {
                case "put" -> PUT;
                case "get" -> GET;
                case "delete" -> DELETE;
                case "deleterecursive" -> DELETE_RECURSIVE;
                case "getvaluelength" -> GET_VALUE_LENGTH;
                case "getvaluehash" -> GET_VALUE_HASH;
                case "collectkeys" -> COLLECT_KEYS;
                case "save" -> SAVE;
                case "savereload" -> SAVE_RELOAD;
                case "roothash" -> ROOT_HASH;
                default -> throw new IllegalArgumentException("Unsupported operation type: " + value);
            };
        }
    }

    public static final class Workload {
        private final String name;
        private final int repeat;
        private final List<Operation> operations;

        private Workload(String name, int repeat, List<Operation> operations) {
            this.name = name;
            this.repeat = repeat;
            this.operations = Collections.unmodifiableList(new ArrayList<>(operations));
        }

        static Workload fromRaw(RawWorkload rawWorkload) {
            if (rawWorkload == null || rawWorkload.name == null || rawWorkload.name.isBlank()) {
                throw new IllegalArgumentException("Workload name must not be empty");
            }

            int repeat = rawWorkload.repeat == null || rawWorkload.repeat <= 0 ? 1 : rawWorkload.repeat;
            if (rawWorkload.operations == null || rawWorkload.operations.isEmpty()) {
                throw new IllegalArgumentException("Workload operations must not be empty for " + rawWorkload.name);
            }

            List<Operation> operations = new ArrayList<>(rawWorkload.operations.size());
            for (RawOperation rawOperation : rawWorkload.operations) {
                operations.add(Operation.fromRaw(rawOperation, rawWorkload.name));
            }

            return new Workload(rawWorkload.name, repeat, operations);
        }

        public String name() {
            return name;
        }

        public int repeat() {
            return repeat;
        }

        public List<Operation> operations() {
            return operations;
        }
    }

    public static final class Operation {
        private final OperationType type;
        private final byte[] key;
        private final byte[] value;
        private final int size;

        private Operation(OperationType type, byte[] key, byte[] value, int size) {
            this.type = type;
            this.key = key;
            this.value = value;
            this.size = size;
        }

        static Operation fromRaw(RawOperation rawOperation, String workloadName) {
            if (rawOperation == null) {
                throw new IllegalArgumentException("Workload operation must not be null for " + workloadName);
            }

            OperationType type = OperationType.fromConfig(rawOperation.op);
            byte[] key = decodeHexNullable(rawOperation.keyHex);
            byte[] value = decodeHexNullable(rawOperation.valueHex);
            int size = rawOperation.size == null || rawOperation.size < 0 ? 0 : rawOperation.size;

            switch (type) {
                case PUT -> {
                    requireNotNull(key, "keyHex", type, workloadName);
                    requireNotNull(value, "valueHex", type, workloadName);
                }
                case GET, DELETE, DELETE_RECURSIVE, GET_VALUE_LENGTH, GET_VALUE_HASH ->
                        requireNotNull(key, "keyHex", type, workloadName);
                case COLLECT_KEYS -> {
                    if (size <= 0) {
                        throw new IllegalArgumentException("Operation COLLECT_KEYS requires positive size in workload " + workloadName);
                    }
                }
                case SAVE, SAVE_RELOAD, ROOT_HASH -> {
                    // no-op
                }
                default -> throw new IllegalStateException("Unsupported operation type: " + type);
            }

            return new Operation(type, key, value, size);
        }

        private static void requireNotNull(
                byte[] value,
                String field,
                OperationType type,
                String workloadName) {
            if (value == null) {
                throw new IllegalArgumentException("Operation " + type + " requires " + field + " in workload " + workloadName);
            }
        }

        private static byte[] decodeHexNullable(String maybeHex) {
            if (maybeHex == null || maybeHex.isBlank()) {
                return null;
            }

            String normalized = maybeHex.trim().toLowerCase(Locale.ROOT);
            if (normalized.startsWith("0x")) {
                normalized = normalized.substring(2);
            }

            if ((normalized.length() & 1) == 1) {
                normalized = "0" + normalized;
            }

            if (normalized.isEmpty()) {
                return new byte[0];
            }

            try {
                return Hex.decode(normalized);
            } catch (RuntimeException e) {
                throw new IllegalArgumentException("Invalid hex payload: " + maybeHex, e);
            }
        }

        public OperationType type() {
            return type;
        }

        public byte[] key() {
            return key;
        }

        public byte[] value() {
            return value;
        }

        public int size() {
            return size;
        }
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private static final class RawCorpus {
        public String version;
        public List<RawWorkload> workloads;
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private static final class RawWorkload {
        public String name;
        public Integer repeat;
        public List<RawOperation> operations;
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private static final class RawOperation {
        public String op;
        public String keyHex;
        public String valueHex;
        public Integer size;
    }
}
