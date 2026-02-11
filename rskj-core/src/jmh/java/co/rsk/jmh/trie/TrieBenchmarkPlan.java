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

package co.rsk.jmh.trie;

import co.rsk.core.RskAddress;
import co.rsk.trie.MutableTrie;
import co.rsk.trie.Trie;
import co.rsk.trie.TrieStore;
import co.rsk.trie.TrieStoreImpl;
import co.rsk.trie.engine.MutableTrieFactory;
import co.rsk.trie.engine.TrieEngineType;
import org.ethereum.datasource.HashMapDB;
import org.ethereum.db.TrieKeyMapper;
import org.ethereum.vm.DataWord;
import org.openjdk.jmh.annotations.Level;
import org.openjdk.jmh.annotations.Param;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.Setup;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.annotations.TearDown;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;
import java.util.Optional;

@State(Scope.Thread)
public class TrieBenchmarkPlan {

    @Param({"java", "rust-shadow"})
    public String engine;

    @Param({"true"})
    public boolean failOnMismatch;

    @Param({"256"})
    public int workingSetSize;

    @Param({"96"})
    public int longValueSize;

    private static final Path MASSIVE_UPLOAD_PATH = Paths.get("rskj-core", "src", "test", "resources", "trie", "massive-upload.dmp");
    private static final Path MASSIVE_UPLOAD_FALLBACK_PATH = Paths.get("src", "test", "resources", "trie", "massive-upload.dmp");

    private final TrieKeyMapper trieKeyMapper = new TrieKeyMapper();
    private final RskAddress storageAddress = new RskAddress(new byte[20]);
    private final List<byte[]> keys = new ArrayList<>();
    private final List<byte[]> values = new ArrayList<>();
    private final List<byte[]> longValues = new ArrayList<>();

    private TrieStore trieStore;
    private MutableTrieFactory mutableTrieFactory;
    private MutableTrie mutableTrie;
    private List<KeyValuePair> massiveUploadEntries = Collections.emptyList();
    private int cursor;

    @Setup(Level.Trial)
    public void setupTrial() {
        for (int i = 0; i < workingSetSize; i++) {
            keys.add(("bench-key-" + i).getBytes(StandardCharsets.UTF_8));
            values.add(("bench-value-" + i).getBytes(StandardCharsets.UTF_8));
            longValues.add(buildLongValue(i));
        }

        massiveUploadEntries = loadMassiveUploadEntries();
    }

    @Setup(Level.Iteration)
    public void setupIteration() {
        trieStore = new TrieStoreImpl(new HashMapDB());
        mutableTrieFactory = new MutableTrieFactory(
                TrieEngineType.fromConfig(engine),
                failOnMismatch,
                null
        );
        mutableTrie = mutableTrieFactory.create(trieStore, new Trie(trieStore));
        cursor = 0;

        seedStorageSubtree();
    }

    @TearDown(Level.Iteration)
    public void tearDownIteration() {
        if (trieStore != null) {
            trieStore.dispose();
        }
    }

    public MutableTrie mutableTrie() {
        return mutableTrie;
    }

    public byte[] nextKey() {
        int index = nextIndex();
        return keys.get(index);
    }

    public byte[] nextValue() {
        int index = nextIndex();
        return values.get(index);
    }

    public byte[] nextLongValue() {
        int index = nextIndex();
        return longValues.get(index);
    }

    public void saveAndReload() {
        mutableTrie.save();
        byte[] rootHash = mutableTrie.getHash().getBytes();
        Optional<Trie> maybeRoot = trieStore.retrieve(rootHash);
        Trie root = maybeRoot.orElseThrow(() -> new IllegalStateException("Saved trie root was not found"));
        mutableTrie = mutableTrieFactory.create(trieStore, root);
    }

    public int iterateStorageKeys() {
        Iterator<DataWord> iterator = mutableTrie.getStorageKeys(storageAddress);
        int count = 0;
        while (iterator.hasNext()) {
            iterator.next();
            count++;
        }
        return count;
    }

    public void replayMassiveUploadDataset() {
        for (KeyValuePair entry : massiveUploadEntries) {
            mutableTrie.put(entry.key, entry.value);
        }
    }

    private int nextIndex() {
        int current = cursor % workingSetSize;
        cursor++;
        return current;
    }

    private void seedStorageSubtree() {
        for (int i = 0; i < 64; i++) {
            byte[] storageKey = trieKeyMapper.getAccountStorageKey(storageAddress, DataWord.valueOf(i));
            mutableTrie.put(storageKey, values.get(i % values.size()));
        }
    }

    private byte[] buildLongValue(int seed) {
        byte[] base = ("bench-long-value-" + seed + "-").getBytes(StandardCharsets.UTF_8);
        byte[] value = new byte[Math.max(longValueSize, base.length)];
        for (int i = 0; i < value.length; i++) {
            value[i] = base[i % base.length];
        }
        return value;
    }

    private List<KeyValuePair> loadMassiveUploadEntries() {
        Path path = Files.exists(MASSIVE_UPLOAD_PATH) ? MASSIVE_UPLOAD_PATH : MASSIVE_UPLOAD_FALLBACK_PATH;
        if (!Files.exists(path)) {
            throw new IllegalStateException("Could not find massive-upload dataset at " + MASSIVE_UPLOAD_PATH);
        }

        try {
            List<KeyValuePair> entries = new ArrayList<>();
            for (String line : Files.readAllLines(path, StandardCharsets.UTF_8)) {
                int separator = line.indexOf('=');
                if (separator <= 0) {
                    continue;
                }

                byte[] key = line.substring(0, separator).getBytes(StandardCharsets.UTF_8);
                byte[] value = line.substring(separator + 1).getBytes(StandardCharsets.UTF_8);
                entries.add(new KeyValuePair(key, value));
            }
            return entries;
        } catch (IOException e) {
            throw new IllegalStateException("Could not load dataset from " + path, e);
        }
    }

    private static class KeyValuePair {
        private final byte[] key;
        private final byte[] value;

        private KeyValuePair(byte[] key, byte[] value) {
            this.key = key;
            this.value = value;
        }
    }
}
