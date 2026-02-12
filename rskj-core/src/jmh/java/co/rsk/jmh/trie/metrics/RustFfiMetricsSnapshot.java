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

import co.rsk.trie.engine.rust.RustUnitriePerfCounters;

public final class RustFfiMetricsSnapshot {

    private final long jniCalls;
    private final long ffiDecodeNanos;
    private final long ffiEncodeNanos;
    private final long coreRuntimeNanos;
    private final long storeCallbackNanos;
    private final long storeCallbackCalls;
    private final long jniBytesIn;
    private final long jniBytesOut;

    public RustFfiMetricsSnapshot(
            long jniCalls,
            long ffiDecodeNanos,
            long ffiEncodeNanos,
            long coreRuntimeNanos,
            long storeCallbackNanos,
            long storeCallbackCalls,
            long jniBytesIn,
            long jniBytesOut) {
        this.jniCalls = jniCalls;
        this.ffiDecodeNanos = ffiDecodeNanos;
        this.ffiEncodeNanos = ffiEncodeNanos;
        this.coreRuntimeNanos = coreRuntimeNanos;
        this.storeCallbackNanos = storeCallbackNanos;
        this.storeCallbackCalls = storeCallbackCalls;
        this.jniBytesIn = jniBytesIn;
        this.jniBytesOut = jniBytesOut;
    }

    public static RustFfiMetricsSnapshot fromCounters(RustUnitriePerfCounters counters) {
        return new RustFfiMetricsSnapshot(
                counters.getJniCalls(),
                counters.getFfiDecodeNanos(),
                counters.getFfiEncodeNanos(),
                counters.getCoreRuntimeNanos(),
                counters.getStoreCallbackNanos(),
                counters.getStoreCallbackCalls(),
                counters.getJniBytesIn(),
                counters.getJniBytesOut()
        );
    }

    public static RustFfiMetricsSnapshot empty() {
        return new RustFfiMetricsSnapshot(0, 0, 0, 0, 0, 0, 0, 0);
    }

    public RustFfiMetricsDelta diffTo(RustFfiMetricsSnapshot newer) {
        return RustFfiMetricsDelta.from(this, newer);
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
}
