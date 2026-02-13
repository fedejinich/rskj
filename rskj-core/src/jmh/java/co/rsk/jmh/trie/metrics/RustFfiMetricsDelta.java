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

package co.rsk.jmh.trie.metrics;

public final class RustFfiMetricsDelta {

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

    private RustFfiMetricsDelta(
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

    public static RustFfiMetricsDelta from(RustFfiMetricsSnapshot older, RustFfiMetricsSnapshot newer) {
        return new RustFfiMetricsDelta(
                nonNegativeDelta(older.getJniCalls(), newer.getJniCalls()),
                nonNegativeDelta(older.getFfiDecodeNanos(), newer.getFfiDecodeNanos()),
                nonNegativeDelta(older.getFfiEncodeNanos(), newer.getFfiEncodeNanos()),
                nonNegativeDelta(older.getCoreRuntimeNanos(), newer.getCoreRuntimeNanos()),
                nonNegativeDelta(older.getStoreCallbackNanos(), newer.getStoreCallbackNanos()),
                nonNegativeDelta(older.getStoreCallbackCalls(), newer.getStoreCallbackCalls()),
                nonNegativeDelta(older.getJniBytesIn(), newer.getJniBytesIn()),
                nonNegativeDelta(older.getJniBytesOut(), newer.getJniBytesOut()),
                nonNegativeDelta(older.getNodesLoadedFromStore(), newer.getNodesLoadedFromStore()),
                nonNegativeDelta(older.getNodesDecoded(), newer.getNodesDecoded()),
                nonNegativeDelta(older.getNodesSaved(), newer.getNodesSaved()),
                nonNegativeDelta(older.getDirtyNodesSaved(), newer.getDirtyNodesSaved()),
                nonNegativeDelta(older.getRehydrateRootOnlyCount(), newer.getRehydrateRootOnlyCount()),
                nonNegativeDelta(older.getRehydrateFullScanFallbackCount(), newer.getRehydrateFullScanFallbackCount())
        );
    }

    private static long nonNegativeDelta(long older, long newer) {
        return newer >= older ? newer - older : 0L;
    }

    public static RustFfiMetricsDelta empty() {
        return new RustFfiMetricsDelta(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
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
}
