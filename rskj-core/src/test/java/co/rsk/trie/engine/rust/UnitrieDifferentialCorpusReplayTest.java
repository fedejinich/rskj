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
package co.rsk.trie.engine.rust;

import co.rsk.core.RskAddress;
import co.rsk.core.types.ints.Uint24;
import co.rsk.crypto.Keccak256;
import co.rsk.db.MutableTrieImpl;
import co.rsk.trie.MutableTrie;
import co.rsk.trie.Trie;
import co.rsk.trie.TrieStore;
import co.rsk.trie.TrieStoreImpl;
import co.rsk.trie.engine.TrieEngineType;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.bouncycastle.util.encoders.Hex;
import org.ethereum.datasource.HashMapDB;
import org.ethereum.db.ByteArrayWrapper;
import org.ethereum.vm.DataWord;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.net.URISyntaxException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Comparator;
import java.util.Iterator;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

class UnitrieDifferentialCorpusReplayTest {

    private static final ObjectMapper JSON_MAPPER = new ObjectMapper();

    @TempDir
    Path tempDir;

    @BeforeEach
    void resetBridge() {
        RustUnitrieBridge.resetForTesting();
    }

    @Test
    void replaysHappyCorpusAndChecksStepByStepRootParity() throws IOException, URISyntaxException {
        assumeTrue(RustUnitrieBridge.load(null).isAvailable(), "unitrie-rs JNI library is unavailable in this environment");

        List<Path> corpusFiles = loadCorpusFiles("trie/differential");
        assertFalse(corpusFiles.isEmpty(), "expected at least one differential corpus file");

        for (Path corpusFile : corpusFiles) {
            List<CorpusStep> steps = readCorpus(corpusFile);
            replayCorpus(corpusFile.getFileName().toString(), steps);
        }
    }

    @Test
    void mismatchEntryFailsDeterministically() {
        List<CorpusStep> steps = List.of(
                new CorpusStep("put", "aa", "01", null, null),
                new CorpusStep("get", "aa", null, null, "simulated mismatch")
        );

        try {
            replayCorpus("synthetic-mismatch", steps);
        } catch (IllegalStateException expected) {
            assertEquals("Corpus synthetic-mismatch contains mismatch marker at step 1", expected.getMessage());
            return;
        }

        throw new AssertionError("expected mismatch marker to fail replay deterministically");
    }

    private static void replayCorpus(String corpusName, List<CorpusStep> steps) {
        for (int i = 0; i < steps.size(); i++) {
            CorpusStep step = steps.get(i);
            if (step.mismatchMessage != null && !step.mismatchMessage.isBlank()) {
                throw new IllegalStateException("Corpus " + corpusName + " contains mismatch marker at step " + i);
            }
        }

        TrieStore javaStore = new TrieStoreImpl(new HashMapDB());
        TrieStore rustStore = new TrieStoreImpl(new HashMapDB());
        MutableTrie javaTrie = new MutableTrieImpl(javaStore, new Trie(javaStore));
        MutableTrie rustTrie = new RustMutableTrie(
                rustStore,
                new Trie(rustStore),
                TrieEngineType.RUST,
                true,
                null
        );

        for (CorpusStep step : steps) {
            applyStep(javaTrie, rustTrie, step);
            assertArrayEquals(
                    javaTrie.getHash().getBytes(),
                    rustTrie.getHash().getBytes(),
                    "state root mismatch while replaying operation " + step.op
            );
        }
    }

    private static void applyStep(MutableTrie javaTrie, MutableTrie rustTrie, CorpusStep step) {
        byte[] key = decodeNullableHex(step.keyHex);
        byte[] value = decodeNullableHex(step.valueHex);

        switch (step.op) {
            case "put":
                javaTrie.put(key, value);
                rustTrie.put(key, value);
                break;
            case "delete":
                javaTrie.put(key, null);
                rustTrie.put(key, null);
                break;
            case "get":
                assertArrayEquals(javaTrie.get(key), rustTrie.get(key));
                break;
            case "deleteRecursive":
                javaTrie.deleteRecursive(key);
                rustTrie.deleteRecursive(key);
                break;
            case "getValueLength":
                Uint24 javaLength = javaTrie.getValueLength(key);
                Uint24 rustLength = rustTrie.getValueLength(key);
                assertEquals(javaLength, rustLength);
                break;
            case "getValueHash":
                Optional<Keccak256> javaHash = javaTrie.getValueHash(key);
                Optional<Keccak256> rustHash = rustTrie.getValueHash(key);
                assertEquals(javaHash.map(Keccak256::getBytes).map(Hex::toHexString),
                        rustHash.map(Keccak256::getBytes).map(Hex::toHexString));
                break;
            case "collectKeys":
                int size = step.size == null ? Integer.MAX_VALUE : step.size;
                Set<ByteArrayWrapper> javaKeys = javaTrie.collectKeys(size);
                Set<ByteArrayWrapper> rustKeys = rustTrie.collectKeys(size);
                assertEquals(javaKeys, rustKeys);
                break;
            case "getStorageKeys":
                byte[] accountBytes = key == null ? new byte[RskAddress.LENGTH_IN_BYTES] : key;
                RskAddress account = new RskAddress(accountBytes);
                List<DataWord> javaStorageKeys = toList(javaTrie.getStorageKeys(account));
                List<DataWord> rustStorageKeys = toList(rustTrie.getStorageKeys(account));
                assertEquals(javaStorageKeys, rustStorageKeys);
                break;
            case "save":
                javaTrie.save();
                rustTrie.save();
                break;
            case "mismatch":
            case "probeFinalStateRoot":
            case "probeException":
                throw new IllegalStateException("Corpus contains non-replay operation " + step.op);
            default:
                throw new IllegalArgumentException("Unsupported corpus operation: " + step.op);
        }
    }

    private static List<Path> loadCorpusFiles(String resourceFolder) throws URISyntaxException, IOException {
        Path folder = Path.of(UnitrieDifferentialCorpusReplayTest.class.getClassLoader().getResource(resourceFolder).toURI());
        try (var stream = Files.list(folder)) {
            return stream
                    .filter(path -> path.getFileName().toString().endsWith(".jsonl"))
                    .sorted(Comparator.comparing(path -> path.getFileName().toString()))
                    .collect(Collectors.toList());
        }
    }

    private static List<CorpusStep> readCorpus(Path corpusPath) throws IOException {
        return Files.readAllLines(corpusPath).stream()
                .filter(line -> !line.isBlank())
                .map(UnitrieDifferentialCorpusReplayTest::parseStep)
                .collect(Collectors.toList());
    }

    private static CorpusStep parseStep(String line) {
        try {
            return JSON_MAPPER.readValue(line, CorpusStep.class);
        } catch (IOException e) {
            throw new IllegalStateException("Could not parse corpus line: " + line, e);
        }
    }

    private static List<DataWord> toList(Iterator<DataWord> iterator) {
        var output = new java.util.ArrayList<DataWord>();
        iterator.forEachRemaining(output::add);
        return output;
    }

    private static byte[] decodeNullableHex(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return Hex.decode(value);
    }

    @SuppressWarnings("unused")
    private static final class CorpusStep {
        public String op;
        public String keyHex;
        public String valueHex;
        public Integer size;
        public String mismatchMessage;

        CorpusStep() {
        }

        private CorpusStep(String op, String keyHex, String valueHex, Integer size, String mismatchMessage) {
            this.op = op;
            this.keyHex = keyHex;
            this.valueHex = valueHex;
            this.size = size;
            this.mismatchMessage = mismatchMessage;
        }
    }
}
