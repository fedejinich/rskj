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

public final class TrieStoreMetricsSnapshot {

    private final long getOps;
    private final long putOps;
    private final long deleteOps;
    private final long updateBatchOps;
    private final long flushOps;
    private final long bytesRead;
    private final long bytesWrittenKeys;
    private final long bytesWrittenValues;

    public TrieStoreMetricsSnapshot(
            long getOps,
            long putOps,
            long deleteOps,
            long updateBatchOps,
            long flushOps,
            long bytesRead,
            long bytesWrittenKeys,
            long bytesWrittenValues) {
        this.getOps = getOps;
        this.putOps = putOps;
        this.deleteOps = deleteOps;
        this.updateBatchOps = updateBatchOps;
        this.flushOps = flushOps;
        this.bytesRead = bytesRead;
        this.bytesWrittenKeys = bytesWrittenKeys;
        this.bytesWrittenValues = bytesWrittenValues;
    }

    public long getGetOps() {
        return getOps;
    }

    public long getPutOps() {
        return putOps;
    }

    public long getDeleteOps() {
        return deleteOps;
    }

    public long getUpdateBatchOps() {
        return updateBatchOps;
    }

    public long getFlushOps() {
        return flushOps;
    }

    public long getBytesRead() {
        return bytesRead;
    }

    public long getBytesWrittenKeys() {
        return bytesWrittenKeys;
    }

    public long getBytesWrittenValues() {
        return bytesWrittenValues;
    }

    public TrieStoreMetricsDelta diffTo(TrieStoreMetricsSnapshot newer) {
        return TrieStoreMetricsDelta.from(this, newer);
    }
}
