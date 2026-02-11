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

import org.openjdk.jmh.annotations.AuxCounters;
import org.openjdk.jmh.annotations.Level;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.Setup;
import org.openjdk.jmh.annotations.State;

@State(Scope.Thread)
@AuxCounters(AuxCounters.Type.EVENTS)
public class TrieBenchmarkAuxCounters {

    public long store_get_ops;
    public long store_put_ops;
    public long store_delete_ops;
    public long store_bytes_read;
    public long store_bytes_written_key;
    public long store_bytes_written_value;

    @Setup(Level.Iteration)
    public void reset() {
        store_get_ops = 0;
        store_put_ops = 0;
        store_delete_ops = 0;
        store_bytes_read = 0;
        store_bytes_written_key = 0;
        store_bytes_written_value = 0;
    }

    public void record(TrieStoreMetricsDelta delta) {
        store_get_ops += delta.getGetOps();
        store_put_ops += delta.getPutOps();
        store_delete_ops += delta.getDeleteOps();
        store_bytes_read += delta.getBytesRead();
        store_bytes_written_key += delta.getBytesWrittenKeys();
        store_bytes_written_value += delta.getBytesWrittenValues();
    }
}
