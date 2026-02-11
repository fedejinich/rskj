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
import co.rsk.trie.IterationElement;
import co.rsk.trie.MutableTrie;
import co.rsk.trie.Trie;
import co.rsk.trie.TrieStore;
import co.rsk.trie.engine.TrieEngineType;
import co.rsk.trie.engine.rust.diagnostics.TrieDifferentialRecorder;
import org.ethereum.db.ByteArrayWrapper;
import org.ethereum.util.ByteUtil;
import org.ethereum.vm.DataWord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.annotation.Nullable;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Iterator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;

/**
 * MutableTrie implementation backed by unitrie-rs through JNI.
 *
 * In {@code engine=rust}, Rust is the source of truth and Java is used as a compatibility mirror for APIs that still
 * depend on {@link Trie}.
 *
 * In {@code engine=rust-shadow}, Java remains the source of truth and Rust is used for deterministic checks.
 */
public class RustMutableTrie implements MutableTrie {

    private static final Logger logger = LoggerFactory.getLogger(RustMutableTrie.class);
    @Nullable
    private static final Field TRIE_HASH_FIELD = findTrieHashField();

    private final TrieStore trieStore;
    private final TrieEngineType engineType;
    private final boolean failOnMismatch;
    private final RustUnitrieImplementation rustImplementation;
    private final RustTrieStoreAdapter storeAdapter;
    @Nullable
    private final MutableTrie javaDelegate;
    private MutableTrie javaMirror;
    private final boolean maintainJavaMirrorOnRust;
    private boolean mirrorDirty;
    @Nullable
    private final RustUnitrieBridge bridge;
    private final long nativeHandle;
    private final boolean rootComparisonEnabled;
    private final TrieDifferentialRecorder differentialRecorder;

    public RustMutableTrie(
            TrieStore trieStore,
            Trie trie,
            TrieEngineType engineType,
            boolean failOnMismatch,
            @Nullable String rustLibraryPath) {
        this(
                trieStore,
                trie,
                engineType,
                failOnMismatch,
                rustLibraryPath,
                RustUnitrieImplementation.LEGACY_V1,
                TrieDifferentialRecorder.noop()
        );
    }

    public RustMutableTrie(
            TrieStore trieStore,
            Trie trie,
            TrieEngineType engineType,
            boolean failOnMismatch,
            @Nullable String rustLibraryPath,
            RustUnitrieImplementation rustImplementation,
            TrieDifferentialRecorder differentialRecorder) {
        this.trieStore = Objects.requireNonNull(trieStore, "trieStore");
        this.engineType = Objects.requireNonNull(engineType, "engineType");
        this.failOnMismatch = failOnMismatch;
        this.rustImplementation = Objects.requireNonNull(rustImplementation, "rustImplementation");
        this.differentialRecorder = Objects.requireNonNull(differentialRecorder, "differentialRecorder");
        this.storeAdapter = new RustTrieStoreAdapter(trieStore);
        this.javaDelegate = engineType == TrieEngineType.RUST_SHADOW ? new MutableTrieImpl(trieStore, trie) : null;
        this.javaMirror = new MutableTrieImpl(trieStore, trie);
        this.maintainJavaMirrorOnRust = rustImplementation != RustUnitrieImplementation.NEXT;
        this.mirrorDirty = false;

        RustUnitrieBridge loadedBridge = RustUnitrieBridge.load(rustLibraryPath);
        if (!loadedBridge.isAvailable()) {
            this.bridge = null;
            this.nativeHandle = 0L;
            this.rootComparisonEnabled = false;
            if (engineType == TrieEngineType.RUST) {
                throw new IllegalStateException("Rust unitrie engine selected but JNI bridge is unavailable");
            }
            return;
        }

        this.bridge = loadedBridge;
        InitializationResult initialization = initializeNativeTrie(trie);
        this.nativeHandle = initialization.handle;
        this.rootComparisonEnabled = initialization.rootComparisonEnabled;

        if (engineType == TrieEngineType.RUST_SHADOW && rootComparisonEnabled) {
            compareRustRoot("constructor");
        }
    }

    @Override
    public Trie getTrie() {
        if (engineType == TrieEngineType.RUST_SHADOW && javaDelegate != null) {
            return javaDelegate.getTrie();
        }

        if (engineType == TrieEngineType.RUST && bridge != null) {
            if (!maintainJavaMirrorOnRust && mirrorDirty) {
                reloadMirrorFromStore();
            }
            Trie mirrorTrie = javaMirror.getTrie();
            tryOverrideTrieHash(mirrorTrie, bridge.currentRootHash(nativeHandle));
            return mirrorTrie;
        }

        return javaMirror.getTrie();
    }

    @Override
    public Keccak256 getHash() {
        if (engineType == TrieEngineType.RUST && bridge != null) {
            return new Keccak256(bridge.currentRootHash(nativeHandle));
        }

        return javaDelegateOrMirror().getHash();
    }

    @Override
    public byte[] get(byte[] key) {
        if (engineType == TrieEngineType.RUST && bridge != null) {
            byte[] value = bridge.get(nativeHandle, key);
            recordDifferentialOperation("get", key, value, value == null ? null : value.length, null, null, null);
            return value;
        }

        byte[] javaValue = javaDelegateOrMirror().get(key);
        compareRustValue("get", key, javaValue);
        recordDifferentialOperation("get", key, javaValue, javaValue == null ? null : javaValue.length, null, null, null);
        return javaValue;
    }

    @Override
    public void put(byte[] key, byte[] value) {
        if (engineType == TrieEngineType.RUST && bridge != null) {
            if (value == null) {
                bridge.delete(nativeHandle, key);
                recordDifferentialOperation("delete", key, null, null, null, null, null);
            } else {
                bridge.put(nativeHandle, key, value);
                recordDifferentialOperation("put", key, value, value.length, null, null, null);
            }

            if (maintainJavaMirrorOnRust) {
                javaMirror.put(key, value);
            } else {
                mirrorDirty = true;
            }
            return;
        }

        MutableTrie javaSource = javaDelegateOrMirror();
        javaSource.put(key, value);
        if (bridge != null) {
            if (value == null) {
                bridge.delete(nativeHandle, key);
                recordDifferentialOperation("delete", key, null, null, null, null, null);
            } else {
                bridge.put(nativeHandle, key, value);
                recordDifferentialOperation("put", key, value, value.length, null, null, null);
            }
            compareRustTransition("put", key, javaSource.get(key));
        }
    }

    @Override
    public void put(ByteArrayWrapper key, byte[] value) {
        put(key.getData(), value);
    }

    @Override
    public void put(String key, byte[] value) {
        byte[] encodedKey = key.getBytes(StandardCharsets.UTF_8);
        put(encodedKey, value);
    }

    @Override
    public Uint24 getValueLength(byte[] key) {
        if (engineType == TrieEngineType.RUST && bridge != null) {
            int valueLength = bridge.getValueLength(nativeHandle, key);
            recordDifferentialOperation("getValueLength", key, null, valueLength < 0 ? null : valueLength, null, null, null);
            return valueLength < 0 ? Uint24.ZERO : new Uint24(valueLength);
        }

        Uint24 javaLength = javaDelegateOrMirror().getValueLength(key);
        if (bridge != null) {
            int rustLength = bridge.getValueLength(nativeHandle, key);
            Uint24 normalizedRustLength = rustLength < 0 ? Uint24.ZERO : new Uint24(rustLength);
            if (!javaLength.equals(normalizedRustLength)) {
                onMismatch(String.format(
                        "unitrie-rs mismatch in getValueLength for key=%s java=%s rust=%s",
                        ByteUtil.toHexString(key),
                        javaLength,
                        normalizedRustLength
                ));
            }
        }
        recordDifferentialOperation("getValueLength", key, null, javaLength.intValue(), null, null, null);
        return javaLength;
    }

    @Override
    public Optional<Keccak256> getValueHash(byte[] key) {
        if (engineType == TrieEngineType.RUST && bridge != null) {
            byte[] valueHash = bridge.getValueHash(nativeHandle, key);
            recordDifferentialOperation("getValueHash", key, null, null, valueHash, null, null);
            return valueHash == null ? Optional.empty() : Optional.of(new Keccak256(valueHash));
        }

        Optional<Keccak256> javaHash = javaDelegateOrMirror().getValueHash(key);
        if (bridge != null) {
            byte[] rustHash = bridge.getValueHash(nativeHandle, key);
            byte[] javaHashBytes = javaHash.map(Keccak256::getBytes).orElse(null);
            if (!Arrays.equals(javaHashBytes, rustHash)) {
                onMismatch(String.format(
                        "unitrie-rs mismatch in getValueHash for key=%s java=%s rust=%s",
                        ByteUtil.toHexString(key),
                        nullableHex(javaHashBytes),
                        nullableHex(rustHash)
                ));
            }
        }
        recordDifferentialOperation("getValueHash", key, null, null, javaHash.map(Keccak256::getBytes).orElse(null), null, null);

        return javaHash;
    }

    @Override
    public Iterator<DataWord> getStorageKeys(RskAddress addr) {
        if (engineType == TrieEngineType.RUST && bridge != null) {
            Iterator<byte[]> keys = bridge.getStorageKeys(nativeHandle, addr.getBytes());
            recordDifferentialOperation("getStorageKeys", addr.getBytes(), null, null, null, null, null);
            return new Iterator<>() {
                @Override
                public boolean hasNext() {
                    return keys.hasNext();
                }

                @Override
                public DataWord next() {
                    return DataWord.valueOf(keys.next());
                }
            };
        }

        Iterator<DataWord> javaKeysIterator = javaDelegateOrMirror().getStorageKeys(addr);
        if (bridge == null) {
            return javaKeysIterator;
        }

        List<byte[]> javaKeys = consumeStorageKeys(javaKeysIterator);
        List<byte[]> rustKeys = consumeStorageKeys(bridge.getStorageKeys(nativeHandle, addr.getBytes()));
        if (!byteListEquals(javaKeys, rustKeys)) {
            onMismatch(String.format(
                    "unitrie-rs mismatch in getStorageKeys for account=%s javaCount=%s rustCount=%s",
                    ByteUtil.toHexString(addr.getBytes()),
                    javaKeys.size(),
                    rustKeys.size()
            ));
        }
        recordDifferentialOperation("getStorageKeys", addr.getBytes(), null, null, null, null, null);

        return toDataWordIterator(javaKeys);
    }

    @Override
    public void deleteRecursive(byte[] key) {
        if (engineType == TrieEngineType.RUST && bridge != null) {
            bridge.deleteRecursive(nativeHandle, key);
            if (maintainJavaMirrorOnRust) {
                javaMirror.deleteRecursive(key);
            } else {
                mirrorDirty = true;
            }
            recordDifferentialOperation("deleteRecursive", key, null, null, null, null, null);
            return;
        }

        MutableTrie javaSource = javaDelegateOrMirror();
        javaSource.deleteRecursive(key);
        if (bridge != null) {
            bridge.deleteRecursive(nativeHandle, key);
            compareRustTransition("deleteRecursive", key, javaSource.get(key));
        }
        recordDifferentialOperation("deleteRecursive", key, null, null, null, null, null);
    }

    @Override
    public void save() {
        if (engineType == TrieEngineType.RUST && bridge != null) {
            bridge.save(nativeHandle, storeAdapter);
            if (maintainJavaMirrorOnRust) {
                reloadMirrorFromStore();
            } else {
                mirrorDirty = true;
            }
            recordDifferentialOperation("save", null, null, null, null, null, null);
            return;
        }

        MutableTrie javaSource = javaDelegateOrMirror();
        javaSource.save();
        if (bridge != null) {
            bridge.save(nativeHandle, storeAdapter);
            compareRustRoot("save");
        }
        recordDifferentialOperation("save", null, null, null, null, null, null);
    }

    @Override
    public void commit() {
        javaDelegateOrMirror().commit();
    }

    @Override
    public void rollback() {
        javaDelegateOrMirror().rollback();
    }

    @Override
    public Set<ByteArrayWrapper> collectKeys(int size) {
        if (engineType == TrieEngineType.RUST && bridge != null) {
            List<byte[]> rustKeys = bridge.collectKeys(nativeHandle, size);
            Set<ByteArrayWrapper> result = new LinkedHashSet<>(rustKeys.size());
            for (byte[] key : rustKeys) {
                result.add(new ByteArrayWrapper(key));
            }
            recordDifferentialOperation("collectKeys", null, null, null, null, size, null);
            return result;
        }

        Set<ByteArrayWrapper> javaKeys = javaDelegateOrMirror().collectKeys(size);
        if (bridge != null) {
            List<byte[]> rustKeys = bridge.collectKeys(nativeHandle, size);
            Set<ByteArrayWrapper> rustKeySet = new LinkedHashSet<>(rustKeys.size());
            for (byte[] key : rustKeys) {
                rustKeySet.add(new ByteArrayWrapper(key));
            }

            if (!javaKeys.equals(rustKeySet)) {
                onMismatch(String.format(
                        "unitrie-rs mismatch in collectKeys for size=%s javaCount=%s rustCount=%s",
                        size,
                        javaKeys.size(),
                        rustKeySet.size()
                ));
            }
        }
        recordDifferentialOperation("collectKeys", null, null, null, null, size, null);

        return javaKeys;
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

    private InitializationResult initializeNativeTrie(Trie trie) {
        Objects.requireNonNull(bridge, "bridge");

        if (engineType == TrieEngineType.RUST) {
            return initializeRustSourceTrie(trie);
        }

        try {
            long handle = bridge.createTrieFromRoot(
                    trie.getHash().getBytes(),
                    storeAdapter,
                    rustImplementation.getConfigName()
            );
            if (handle > 0) {
                return new InitializationResult(handle, true);
            }
        } catch (RuntimeException e) {
            logger.info("Could not initialize rust-shadow trie from persisted root, continuing with empty native trie: {}", e.getMessage());
            logger.debug("Rust-shadow initialization fallback", e);
        }

        return new InitializationResult(bridge.createTrie(rustImplementation.getConfigName()), false);
    }

    private InitializationResult initializeRustSourceTrie(Trie trie) {
        Objects.requireNonNull(bridge, "bridge");

        try {
            long handle = bridge.createTrieFromRoot(
                    trie.getHash().getBytes(),
                    storeAdapter,
                    rustImplementation.getConfigName()
            );
            if (handle > 0) {
                return new InitializationResult(handle, true);
            }
        } catch (RuntimeException e) {
            logger.info("Could not initialize rust trie from persisted root, bootstrapping from Java trie snapshot: {}", e.getMessage());
            logger.debug("Rust trie initialization fallback", e);
        }

        long handle = bridge.createTrie(rustImplementation.getConfigName());
        bootstrapRustFromJavaTrie(handle, trie);
        return new InitializationResult(handle, true);
    }

    private void bootstrapRustFromJavaTrie(long handle, Trie trie) {
        if (bridge == null) {
            return;
        }

        Iterator<IterationElement> iterator = trie.getPreOrderIterator();
        while (iterator.hasNext()) {
            IterationElement element = iterator.next();
            byte[] value = element.getNode().getValue();
            if (value == null || value.length == 0) {
                continue;
            }

            byte[] key = element.getNodeKey().encode();
            bridge.put(handle, key, value);
        }
    }

    private boolean reloadMirrorFromStore() {
        if (bridge == null) {
            return false;
        }

        byte[] currentRoot = bridge.currentRootHash(nativeHandle);
        Optional<Trie> maybeTrie = trieStore.retrieve(currentRoot);
        if (maybeTrie.isPresent()) {
            javaMirror = new MutableTrieImpl(trieStore, maybeTrie.get());
            mirrorDirty = false;
            return true;
        }

        logger.warn("Rust save completed but root {} could not be retrieved from TrieStore", ByteUtil.toHexString(currentRoot));
        return false;
    }

    private MutableTrie javaDelegateOrMirror() {
        return javaDelegate == null ? javaMirror : javaDelegate;
    }

    private void compareRustTransition(String operation, byte[] key, @Nullable byte[] javaValue) {
        compareRustValue(operation, key, javaValue);
        compareRustRoot(operation);
    }

    private void compareRustValue(String operation, byte[] key, @Nullable byte[] javaValue) {
        if (bridge == null) {
            return;
        }

        byte[] rustValue = bridge.get(nativeHandle, key);
        if (Arrays.equals(javaValue, rustValue)) {
            return;
        }

        onMismatch(String.format(
                "unitrie-rs mismatch in %s for key=%s java=%s rust=%s",
                operation,
                ByteUtil.toHexString(key),
                nullableHex(javaValue),
                nullableHex(rustValue)
        ));
    }

    private void compareRustRoot(String operation) {
        if (bridge == null || !rootComparisonEnabled) {
            return;
        }

        byte[] rustRoot = bridge.currentRootHash(nativeHandle);
        byte[] javaRoot = javaDelegateOrMirror().getHash().getBytes();
        if (Arrays.equals(javaRoot, rustRoot)) {
            return;
        }

        onMismatch(String.format(
                "unitrie-rs root mismatch in %s javaRoot=%s rustRoot=%s",
                operation,
                ByteUtil.toHexString(javaRoot),
                ByteUtil.toHexString(rustRoot)
        ));
    }

    private void onMismatch(String message) {
        recordDifferentialOperation("mismatch", null, null, null, null, null, message);
        if (failOnMismatch) {
            throw new IllegalStateException(message);
        }

        logger.error(message);
    }

    private void recordDifferentialOperation(
            String operation,
            @Nullable byte[] key,
            @Nullable byte[] value,
            @Nullable Integer valueLength,
            @Nullable byte[] valueHash,
            @Nullable Integer size,
            @Nullable String mismatchMessage) {
        if (!differentialRecorder.isEnabled() || bridge == null || engineType != TrieEngineType.RUST_SHADOW) {
            return;
        }

        try {
            byte[] javaRoot = javaDelegateOrMirror().getHash().getBytes();
            byte[] rustRoot = bridge.currentRootHash(nativeHandle);
            differentialRecorder.recordOperation(
                    operation,
                    key,
                    value,
                    valueLength,
                    valueHash,
                    size,
                    javaRoot,
                    rustRoot,
                    mismatchMessage
            );
        } catch (RuntimeException ex) {
            logger.warn("Could not record trie differential operation {}", operation);
            logger.debug("Trie differential recorder failure", ex);
        }
    }

    private static String nullableHex(@Nullable byte[] value) {
        return value == null ? "null" : ByteUtil.toHexString(value);
    }

    private static List<byte[]> consumeStorageKeys(Iterator<?> iterator) {
        List<byte[]> keys = new ArrayList<>();
        while (iterator.hasNext()) {
            Object next = iterator.next();
            if (next instanceof DataWord) {
                keys.add(((DataWord) next).getData());
            } else if (next instanceof byte[]) {
                keys.add(DataWord.valueOf((byte[]) next).getData());
            } else {
                throw new IllegalStateException("Unexpected storage key iterator payload type");
            }
        }
        return keys;
    }

    private static Iterator<DataWord> toDataWordIterator(List<byte[]> values) {
        return values.stream().map(DataWord::valueOf).iterator();
    }

    private static boolean byteListEquals(List<byte[]> left, List<byte[]> right) {
        if (left.size() != right.size()) {
            return false;
        }

        for (int index = 0; index < left.size(); index++) {
            if (!Arrays.equals(left.get(index), right.get(index))) {
                return false;
            }
        }

        return true;
    }

    @Nullable
    private static Field findTrieHashField() {
        try {
            Field field = Trie.class.getDeclaredField("hash");
            field.setAccessible(true);
            return field;
        } catch (NoSuchFieldException e) {
            logger.warn("Could not resolve Trie.hash field for rust root reflection fallback");
            logger.debug("Trie.hash reflection setup failure", e);
            return null;
        }
    }

    private static void tryOverrideTrieHash(Trie trie, byte[] rootHash) {
        if (TRIE_HASH_FIELD == null) {
            return;
        }

        try {
            TRIE_HASH_FIELD.set(trie, new Keccak256(rootHash));
        } catch (IllegalAccessException e) {
            logger.warn("Could not override trie hash for rust-backed trie");
            logger.debug("Trie.hash reflection write failure", e);
        }
    }

    private static final class InitializationResult {
        private final long handle;
        private final boolean rootComparisonEnabled;

        private InitializationResult(long handle, boolean rootComparisonEnabled) {
            this.handle = handle;
            this.rootComparisonEnabled = rootComparisonEnabled;
        }
    }
}
