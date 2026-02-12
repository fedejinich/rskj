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

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.annotation.Nullable;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;
import java.util.Objects;

public final class RustUnitrieBridge {

    private static final Logger logger = LoggerFactory.getLogger(RustUnitrieBridge.class);
    private static final String DEFAULT_LIBRARY = "unitrie_rs_jni";

    private static final Object LOAD_LOCK = new Object();
    private static volatile boolean loadAttempted;
    private static volatile boolean available;
    @Nullable
    private static volatile String attemptedLibraryPath;

    private RustUnitrieBridge() {
    }

    public static RustUnitrieBridge load(@Nullable String libraryPath) {
        ensureLoaded(libraryPath);
        return new RustUnitrieBridge();
    }

    private static void ensureLoaded(@Nullable String libraryPath) {
        if (!shouldAttemptLoad(libraryPath)) {
            return;
        }

        synchronized (LOAD_LOCK) {
            if (!shouldAttemptLoad(libraryPath)) {
                return;
            }

            try {
                if (libraryPath == null) {
                    System.loadLibrary(DEFAULT_LIBRARY);
                } else {
                    System.load(libraryPath);
                }
                available = true;
                logger.info("Loaded unitrie-rs JNI bridge");
            } catch (UnsatisfiedLinkError | SecurityException e) {
                available = false;
                logger.warn("Could not load unitrie-rs JNI bridge: {}", e.getMessage());
                logger.debug("JNI loading error", e);
            } finally {
                loadAttempted = true;
                attemptedLibraryPath = libraryPath;
            }
        }
    }

    private static boolean shouldAttemptLoad(@Nullable String libraryPath) {
        if (!loadAttempted) {
            return true;
        }

        if (available) {
            return false;
        }

        return !Objects.equals(attemptedLibraryPath, libraryPath);
    }

    static void resetForTesting() {
        synchronized (LOAD_LOCK) {
            loadAttempted = false;
            available = false;
            attemptedLibraryPath = null;
        }
    }

    public boolean isAvailable() {
        return available;
    }

    public long createTrie(String implementation) {
        return nativeCreateTrie(implementation);
    }

    public long createTrieFromRoot(byte[] rootHash, RustTrieStoreAdapter storeAdapter, String implementation) {
        return nativeCreateTrieFromRoot(rootHash, storeAdapter, implementation);
    }

    public void destroyTrie(long handle) {
        nativeDestroyTrie(handle);
    }

    @Nullable
    public byte[] get(long handle, byte[] key) {
        return nativeGet(handle, key);
    }

    public void put(long handle, byte[] key, @Nullable byte[] value) {
        nativePut(handle, key, value);
    }

    public void delete(long handle, byte[] key) {
        nativeDelete(handle, key);
    }

    public void deleteRecursive(long handle, byte[] key) {
        nativeDeleteRecursive(handle, key);
    }

    public void save(long handle, RustTrieStoreAdapter storeAdapter) {
        nativeSave(handle, storeAdapter);
    }

    public int getValueLength(long handle, byte[] key) {
        return nativeGetValueLength(handle, key);
    }

    @Nullable
    public byte[] getValueHash(long handle, byte[] key) {
        return nativeGetValueHash(handle, key);
    }

    public List<byte[]> collectKeys(long handle, int size) {
        byte[][] keys = nativeCollectKeys(handle, size);
        return arrayToList(keys);
    }

    public Iterator<byte[]> getStorageKeys(long handle, byte[] accountAddress) {
        byte[][] keys = nativeGetStorageKeys(handle, accountAddress);
        return arrayToList(keys).iterator();
    }

    @Nullable
    public byte[] getStorageKeysPacked(long handle, byte[] accountAddress) {
        return nativeGetStorageKeysPacked(handle, accountAddress);
    }

    public Iterator<byte[]> getStorageKeysPackedDecoded(long handle, byte[] accountAddress) {
        return decodeStorageKeysPacked(getStorageKeysPacked(handle, accountAddress)).iterator();
    }

    public byte[] rootHash(long handle) {
        return nativeRootHash(handle);
    }

    public byte[] currentRootHash(long handle) {
        return nativeCurrentRootHash(handle);
    }

    public RustUnitriePerfCounters getPerfCounters(long handle) {
        long[] rawCounters = nativeGetPerfCounters(handle);
        return RustUnitriePerfCounters.fromRawCounters(rawCounters);
    }

    public void resetPerfCounters(long handle) {
        nativeResetPerfCounters(handle);
    }

    public long benchmarkNoop(int iterations) {
        return nativeBenchmarkNoop(iterations);
    }

    public long benchmarkRoundtrip(byte[] payload, int iterations) {
        return nativeBenchmarkRoundtrip(payload, iterations);
    }

    private static List<byte[]> arrayToList(@Nullable byte[][] values) {
        if (values == null || values.length == 0) {
            return Collections.emptyList();
        }

        List<byte[]> list = new ArrayList<>(values.length);
        Collections.addAll(list, values);
        return list;
    }

    static List<byte[]> decodeStorageKeysPacked(@Nullable byte[] payload) {
        if (payload == null || payload.length == 0) {
            return Collections.emptyList();
        }

        Cursor cursor = new Cursor();
        long rawCount = decodeVarInt(payload, cursor);
        if (rawCount < 0 || rawCount > Integer.MAX_VALUE) {
            throw new IllegalStateException("Invalid storage key count in packed payload");
        }

        int count = (int) rawCount;
        List<byte[]> keys = new ArrayList<>(count);
        for (int index = 0; index < count; index++) {
            long rawLength = decodeVarInt(payload, cursor);
            if (rawLength < 0 || rawLength > Integer.MAX_VALUE) {
                throw new IllegalStateException("Invalid storage key length in packed payload");
            }

            int length = (int) rawLength;
            int end = cursor.offset + length;
            if (end > payload.length) {
                throw new IllegalStateException("Packed storage keys payload is truncated");
            }

            byte[] key = new byte[length];
            System.arraycopy(payload, cursor.offset, key, 0, length);
            cursor.offset = end;
            keys.add(key);
        }

        if (cursor.offset != payload.length) {
            throw new IllegalStateException("Packed storage keys payload has trailing bytes");
        }

        return keys;
    }

    private static long decodeVarInt(byte[] payload, Cursor cursor) {
        if (cursor.offset >= payload.length) {
            throw new IllegalStateException("Packed storage keys varint is truncated");
        }

        int first = payload[cursor.offset++] & 0xff;
        if (first < 0xfd) {
            return first;
        }

        if (first == 0xfd) {
            return decodeFixed(payload, cursor, 2);
        }
        if (first == 0xfe) {
            return decodeFixed(payload, cursor, 4);
        }
        return decodeFixed(payload, cursor, 8);
    }

    private static long decodeFixed(byte[] payload, Cursor cursor, int size) {
        int end = cursor.offset + size;
        if (end > payload.length) {
            throw new IllegalStateException("Packed storage keys fixed varint is truncated");
        }

        long value = 0L;
        for (int shift = 0; shift < size; shift++) {
            value |= ((long) payload[cursor.offset + shift] & 0xffL) << (shift * 8);
        }
        cursor.offset = end;
        return value;
    }

    private static final class Cursor {
        private int offset = 0;
    }

    private static native long nativeCreateTrie(String implementation);
    private static native long nativeCreateTrieFromRoot(byte[] rootHash, RustTrieStoreAdapter storeAdapter, String implementation);

    private static native void nativeDestroyTrie(long handle);

    private static native byte[] nativeGet(long handle, byte[] key);

    private static native void nativePut(long handle, byte[] key, @Nullable byte[] value);

    private static native void nativeDelete(long handle, byte[] key);

    private static native void nativeDeleteRecursive(long handle, byte[] key);
    private static native void nativeSave(long handle, RustTrieStoreAdapter storeAdapter);

    private static native int nativeGetValueLength(long handle, byte[] key);

    private static native byte[] nativeGetValueHash(long handle, byte[] key);

    private static native byte[][] nativeCollectKeys(long handle, int size);

    private static native byte[][] nativeGetStorageKeys(long handle, byte[] accountAddress);

    private static native byte[] nativeGetStorageKeysPacked(long handle, byte[] accountAddress);

    private static native byte[] nativeRootHash(long handle);

    private static native byte[] nativeCurrentRootHash(long handle);

    private static native long[] nativeGetPerfCounters(long handle);

    private static native void nativeResetPerfCounters(long handle);

    private static native long nativeBenchmarkNoop(int iterations);

    private static native long nativeBenchmarkRoundtrip(byte[] payload, int iterations);
}
