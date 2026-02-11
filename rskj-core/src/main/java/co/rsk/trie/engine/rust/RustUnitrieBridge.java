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

public final class RustUnitrieBridge {

    private static final Logger logger = LoggerFactory.getLogger(RustUnitrieBridge.class);
    private static final String DEFAULT_LIBRARY = "unitrie_rs_jni";

    private static final Object LOAD_LOCK = new Object();
    private static volatile boolean loadAttempted;
    private static volatile boolean available;

    private RustUnitrieBridge() {
    }

    public static RustUnitrieBridge load(@Nullable String libraryPath) {
        ensureLoaded(libraryPath);
        return new RustUnitrieBridge();
    }

    private static void ensureLoaded(@Nullable String libraryPath) {
        if (loadAttempted) {
            return;
        }

        synchronized (LOAD_LOCK) {
            if (loadAttempted) {
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
            }
        }
    }

    public boolean isAvailable() {
        return available;
    }

    public long createTrie() {
        return nativeCreateTrie();
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

    public byte[] rootHash(long handle) {
        return nativeRootHash(handle);
    }

    private static native long nativeCreateTrie();

    private static native void nativeDestroyTrie(long handle);

    private static native byte[] nativeGet(long handle, byte[] key);

    private static native void nativePut(long handle, byte[] key, @Nullable byte[] value);

    private static native void nativeDelete(long handle, byte[] key);

    private static native void nativeDeleteRecursive(long handle, byte[] key);

    private static native byte[] nativeRootHash(long handle);
}
