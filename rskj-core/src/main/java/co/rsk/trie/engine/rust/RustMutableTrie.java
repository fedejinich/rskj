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
import co.rsk.trie.engine.TrieEngineType;
import org.ethereum.db.ByteArrayWrapper;
import org.ethereum.util.ByteUtil;
import org.ethereum.vm.DataWord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.annotation.Nullable;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Iterator;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;

/**
 * MutableTrie implementation with optional rust JNI mirroring.
 *
 * The java implementation remains the source of truth in v1.
 */
public class RustMutableTrie implements MutableTrie {

    private static final Logger logger = LoggerFactory.getLogger(RustMutableTrie.class);

    private final MutableTrie javaDelegate;
    private final TrieEngineType engineType;
    private final boolean failOnMismatch;
    @Nullable
    private final RustUnitrieBridge bridge;
    private final long nativeHandle;

    public RustMutableTrie(
            TrieStore trieStore,
            Trie trie,
            TrieEngineType engineType,
            boolean failOnMismatch,
            @Nullable String rustLibraryPath) {
        this.javaDelegate = new MutableTrieImpl(trieStore, trie);
        this.engineType = Objects.requireNonNull(engineType, "engineType");
        this.failOnMismatch = failOnMismatch;

        RustUnitrieBridge loadedBridge = RustUnitrieBridge.load(rustLibraryPath);
        if (loadedBridge.isAvailable()) {
            this.bridge = loadedBridge;
            this.nativeHandle = bridge.createTrie();
        } else {
            this.bridge = null;
            this.nativeHandle = 0L;
            if (engineType == TrieEngineType.RUST) {
                throw new IllegalStateException("Rust unitrie engine selected but JNI bridge is unavailable");
            }
        }
    }

    @Override
    public Trie getTrie() {
        return javaDelegate.getTrie();
    }

    @Override
    public Keccak256 getHash() {
        return javaDelegate.getHash();
    }

    @Override
    public byte[] get(byte[] key) {
        byte[] javaValue = javaDelegate.get(key);
        warmUpRustValue(key, javaValue);
        compareRustValue("get", key, javaValue);
        return javaValue;
    }

    @Override
    public void put(byte[] key, byte[] value) {
        javaDelegate.put(key, value);
        if (bridge != null) {
            bridge.put(nativeHandle, key, value);
            compareRustValue("put", key, javaDelegate.get(key));
        }
    }

    @Override
    public void put(ByteArrayWrapper key, byte[] value) {
        put(key.getData(), value);
    }

    @Override
    public void put(String key, byte[] value) {
        javaDelegate.put(key, value);
        if (bridge != null) {
            byte[] encodedKey = key.getBytes(StandardCharsets.UTF_8);
            bridge.put(nativeHandle, encodedKey, value);
            compareRustValue("put(String)", encodedKey, javaDelegate.get(encodedKey));
        }
    }

    @Override
    public Uint24 getValueLength(byte[] key) {
        return javaDelegate.getValueLength(key);
    }

    @Override
    public Optional<Keccak256> getValueHash(byte[] key) {
        return javaDelegate.getValueHash(key);
    }

    @Override
    public Iterator<DataWord> getStorageKeys(RskAddress addr) {
        return javaDelegate.getStorageKeys(addr);
    }

    @Override
    public void deleteRecursive(byte[] key) {
        javaDelegate.deleteRecursive(key);
        if (bridge != null) {
            bridge.deleteRecursive(nativeHandle, key);
            compareRustValue("deleteRecursive", key, javaDelegate.get(key));
        }
    }

    @Override
    public void save() {
        javaDelegate.save();
    }

    @Override
    public void commit() {
        javaDelegate.commit();
    }

    @Override
    public void rollback() {
        javaDelegate.rollback();
    }

    @Override
    public Set<ByteArrayWrapper> collectKeys(int size) {
        return javaDelegate.collectKeys(size);
    }

    @Override
    protected void finalize() throws Throwable {
        try {
            if (bridge != null && nativeHandle != 0L) {
                bridge.destroyTrie(nativeHandle);
            }
        } finally {
            super.finalize();
        }
    }

    private void warmUpRustValue(byte[] key, @Nullable byte[] javaValue) {
        if (bridge == null || javaValue == null) {
            return;
        }

        byte[] rustValue = bridge.get(nativeHandle, key);
        if (rustValue == null) {
            bridge.put(nativeHandle, key, javaValue);
        }
    }

    private void compareRustValue(String operation, byte[] key, @Nullable byte[] javaValue) {
        if (bridge == null) {
            return;
        }

        byte[] rustValue = bridge.get(nativeHandle, key);
        if (Arrays.equals(javaValue, rustValue)) {
            return;
        }

        String message = String.format(
                "unitrie-rs mismatch in %s for key=%s java=%s rust=%s",
                operation,
                ByteUtil.toHexString(key),
                nullableHex(javaValue),
                nullableHex(rustValue)
        );

        if (failOnMismatch) {
            throw new IllegalStateException(message);
        }

        logger.error(message);
    }

    private static String nullableHex(@Nullable byte[] value) {
        return value == null ? "null" : ByteUtil.toHexString(value);
    }
}
