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

import org.ethereum.datasource.DataSourceKeyIterator;
import org.ethereum.datasource.KeyValueDataSource;
import org.ethereum.db.ByteArrayWrapper;

import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.concurrent.atomic.AtomicLong;

public class MeasuredKeyValueDataSource implements KeyValueDataSource {

    private final KeyValueDataSource delegate;

    private final AtomicLong getOps = new AtomicLong(0);
    private final AtomicLong putOps = new AtomicLong(0);
    private final AtomicLong deleteOps = new AtomicLong(0);
    private final AtomicLong updateBatchOps = new AtomicLong(0);
    private final AtomicLong flushOps = new AtomicLong(0);

    private final AtomicLong bytesRead = new AtomicLong(0);
    private final AtomicLong bytesWrittenKeys = new AtomicLong(0);
    private final AtomicLong bytesWrittenValues = new AtomicLong(0);

    public MeasuredKeyValueDataSource(KeyValueDataSource delegate) {
        this.delegate = Objects.requireNonNull(delegate, "delegate");
    }

    @Override
    public byte[] get(byte[] key) {
        getOps.incrementAndGet();
        byte[] value = delegate.get(key);
        if (value != null) {
            bytesRead.addAndGet(value.length);
        }

        return value;
    }

    @Override
    public byte[] put(byte[] key, byte[] value) {
        putOps.incrementAndGet();
        bytesWrittenKeys.addAndGet(key.length);
        bytesWrittenValues.addAndGet(value.length);
        return delegate.put(key, value);
    }

    @Override
    public void delete(byte[] key) {
        deleteOps.incrementAndGet();
        bytesWrittenKeys.addAndGet(key.length);
        delegate.delete(key);
    }

    @Override
    public Set<ByteArrayWrapper> keys() {
        return delegate.keys();
    }

    @Override
    public DataSourceKeyIterator keyIterator() {
        return delegate.keyIterator();
    }

    @Override
    public void updateBatch(Map<ByteArrayWrapper, byte[]> entriesToUpdate, Set<ByteArrayWrapper> keysToRemove) {
        updateBatchOps.incrementAndGet();
        entriesToUpdate.forEach((key, value) -> {
            bytesWrittenKeys.addAndGet(key.getData().length);
            bytesWrittenValues.addAndGet(value.length);
        });

        for (ByteArrayWrapper key : keysToRemove) {
            bytesWrittenKeys.addAndGet(key.getData().length);
        }

        delegate.updateBatch(entriesToUpdate, keysToRemove);
    }

    @Override
    public void flush() {
        flushOps.incrementAndGet();
        delegate.flush();
    }

    @Override
    public String getName() {
        return delegate.getName();
    }

    @Override
    public void init() {
        delegate.init();
    }

    @Override
    public boolean isAlive() {
        return delegate.isAlive();
    }

    @Override
    public void close() {
        delegate.close();
    }

    public TrieStoreMetricsSnapshot snapshot() {
        return new TrieStoreMetricsSnapshot(
                getOps.get(),
                putOps.get(),
                deleteOps.get(),
                updateBatchOps.get(),
                flushOps.get(),
                bytesRead.get(),
                bytesWrittenKeys.get(),
                bytesWrittenValues.get()
        );
    }

    public TrieStoreMetricsDelta diffFrom(TrieStoreMetricsSnapshot baseline) {
        return baseline.diffTo(snapshot());
    }
}
