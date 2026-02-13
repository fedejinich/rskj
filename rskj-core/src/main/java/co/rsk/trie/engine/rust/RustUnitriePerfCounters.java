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

public class RustUnitriePerfCounters {
    private final long serializedNodes;
    private final long hashedNodes;
    private final long persistedNodes;
    private final long persistedValues;
    private final long cacheHits;
    private final long cacheMisses;
    private final long jniCalls;
    private final long ffiDecodeNanos;
    private final long ffiEncodeNanos;
    private final long coreRuntimeNanos;
    private final long storeCallbackNanos;
    private final long storeCallbackCalls;
    private final long jniBytesIn;
    private final long jniBytesOut;
    private final long nodesLoadedFromStore;
    private final long nodesDecoded;
    private final long nodesSaved;
    private final long dirtyNodesSaved;
    private final long rehydrateRootOnlyCount;
    private final long rehydrateFullScanFallbackCount;

    public RustUnitriePerfCounters(
            long serializedNodes,
            long hashedNodes,
            long persistedNodes,
            long persistedValues,
            long cacheHits,
            long cacheMisses,
            long jniCalls) {
        this(
                serializedNodes,
                hashedNodes,
                persistedNodes,
                persistedValues,
                cacheHits,
                cacheMisses,
                jniCalls,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0
        );
    }

    public RustUnitriePerfCounters(
            long serializedNodes,
            long hashedNodes,
            long persistedNodes,
            long persistedValues,
            long cacheHits,
            long cacheMisses,
            long jniCalls,
            long ffiDecodeNanos,
            long ffiEncodeNanos,
            long coreRuntimeNanos,
            long storeCallbackNanos,
            long storeCallbackCalls,
            long jniBytesIn,
            long jniBytesOut) {
        this(
                serializedNodes,
                hashedNodes,
                persistedNodes,
                persistedValues,
                cacheHits,
                cacheMisses,
                jniCalls,
                ffiDecodeNanos,
                ffiEncodeNanos,
                coreRuntimeNanos,
                storeCallbackNanos,
                storeCallbackCalls,
                jniBytesIn,
                jniBytesOut,
                0,
                0,
                0,
                0,
                0,
                0
        );
    }

    public RustUnitriePerfCounters(
            long serializedNodes,
            long hashedNodes,
            long persistedNodes,
            long persistedValues,
            long cacheHits,
            long cacheMisses,
            long jniCalls,
            long ffiDecodeNanos,
            long ffiEncodeNanos,
            long coreRuntimeNanos,
            long storeCallbackNanos,
            long storeCallbackCalls,
            long jniBytesIn,
            long jniBytesOut,
            long nodesLoadedFromStore,
            long nodesDecoded,
            long nodesSaved,
            long dirtyNodesSaved,
            long rehydrateRootOnlyCount,
            long rehydrateFullScanFallbackCount) {
        this.serializedNodes = serializedNodes;
        this.hashedNodes = hashedNodes;
        this.persistedNodes = persistedNodes;
        this.persistedValues = persistedValues;
        this.cacheHits = cacheHits;
        this.cacheMisses = cacheMisses;
        this.jniCalls = jniCalls;
        this.ffiDecodeNanos = ffiDecodeNanos;
        this.ffiEncodeNanos = ffiEncodeNanos;
        this.coreRuntimeNanos = coreRuntimeNanos;
        this.storeCallbackNanos = storeCallbackNanos;
        this.storeCallbackCalls = storeCallbackCalls;
        this.jniBytesIn = jniBytesIn;
        this.jniBytesOut = jniBytesOut;
        this.nodesLoadedFromStore = nodesLoadedFromStore;
        this.nodesDecoded = nodesDecoded;
        this.nodesSaved = nodesSaved;
        this.dirtyNodesSaved = dirtyNodesSaved;
        this.rehydrateRootOnlyCount = rehydrateRootOnlyCount;
        this.rehydrateFullScanFallbackCount = rehydrateFullScanFallbackCount;
    }

    public static RustUnitriePerfCounters empty() {
        return new RustUnitriePerfCounters(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    }

    public static RustUnitriePerfCounters fromRawCounters(long[] rawCounters) {
        if (rawCounters == null || rawCounters.length < 7) {
            return empty();
        }

        return new RustUnitriePerfCounters(
                rawCounters[0],
                rawCounters[1],
                rawCounters[2],
                rawCounters[3],
                rawCounters[4],
                rawCounters[5],
                rawCounters[6],
                readRaw(rawCounters, 7),
                readRaw(rawCounters, 8),
                readRaw(rawCounters, 9),
                readRaw(rawCounters, 10),
                readRaw(rawCounters, 11),
                readRaw(rawCounters, 12),
                readRaw(rawCounters, 13),
                readRaw(rawCounters, 14),
                readRaw(rawCounters, 15),
                readRaw(rawCounters, 16),
                readRaw(rawCounters, 17),
                readRaw(rawCounters, 18),
                readRaw(rawCounters, 19)
        );
    }

    private static long readRaw(long[] rawCounters, int index) {
        return index < rawCounters.length ? rawCounters[index] : 0L;
    }

    public long getSerializedNodes() {
        return serializedNodes;
    }

    public long getHashedNodes() {
        return hashedNodes;
    }

    public long getPersistedNodes() {
        return persistedNodes;
    }

    public long getPersistedValues() {
        return persistedValues;
    }

    public long getCacheHits() {
        return cacheHits;
    }

    public long getCacheMisses() {
        return cacheMisses;
    }

    public long getJniCalls() {
        return jniCalls;
    }

    public long getFfiDecodeNanos() {
        return ffiDecodeNanos;
    }

    public long getFfiEncodeNanos() {
        return ffiEncodeNanos;
    }

    public long getCoreRuntimeNanos() {
        return coreRuntimeNanos;
    }

    public long getStoreCallbackNanos() {
        return storeCallbackNanos;
    }

    public long getStoreCallbackCalls() {
        return storeCallbackCalls;
    }

    public long getJniBytesIn() {
        return jniBytesIn;
    }

    public long getJniBytesOut() {
        return jniBytesOut;
    }

    public long getNodesLoadedFromStore() {
        return nodesLoadedFromStore;
    }

    public long getNodesDecoded() {
        return nodesDecoded;
    }

    public long getNodesSaved() {
        return nodesSaved;
    }

    public long getDirtyNodesSaved() {
        return dirtyNodesSaved;
    }

    public long getRehydrateRootOnlyCount() {
        return rehydrateRootOnlyCount;
    }

    public long getRehydrateFullScanFallbackCount() {
        return rehydrateFullScanFallbackCount;
    }

    public RustUnitriePerfCounters plus(RustUnitriePerfCounters other) {
        if (other == null) {
            return this;
        }

        return new RustUnitriePerfCounters(
                serializedNodes + other.serializedNodes,
                hashedNodes + other.hashedNodes,
                persistedNodes + other.persistedNodes,
                persistedValues + other.persistedValues,
                cacheHits + other.cacheHits,
                cacheMisses + other.cacheMisses,
                jniCalls + other.jniCalls,
                ffiDecodeNanos + other.ffiDecodeNanos,
                ffiEncodeNanos + other.ffiEncodeNanos,
                coreRuntimeNanos + other.coreRuntimeNanos,
                storeCallbackNanos + other.storeCallbackNanos,
                storeCallbackCalls + other.storeCallbackCalls,
                jniBytesIn + other.jniBytesIn,
                jniBytesOut + other.jniBytesOut,
                nodesLoadedFromStore + other.nodesLoadedFromStore,
                nodesDecoded + other.nodesDecoded,
                nodesSaved + other.nodesSaved,
                dirtyNodesSaved + other.dirtyNodesSaved,
                rehydrateRootOnlyCount + other.rehydrateRootOnlyCount,
                rehydrateFullScanFallbackCount + other.rehydrateFullScanFallbackCount
        );
    }
}
