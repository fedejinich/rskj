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
    public long rust_jni_calls;
    public long rust_ffi_decode_ns;
    public long rust_ffi_encode_ns;
    public long rust_core_runtime_ns;
    public long rust_store_callback_ns;
    public long rust_store_callback_calls;
    public long rust_jni_bytes_in;
    public long rust_jni_bytes_out;

    @Setup(Level.Iteration)
    public void reset() {
        store_get_ops = 0;
        store_put_ops = 0;
        store_delete_ops = 0;
        store_bytes_read = 0;
        store_bytes_written_key = 0;
        store_bytes_written_value = 0;
        rust_jni_calls = 0;
        rust_ffi_decode_ns = 0;
        rust_ffi_encode_ns = 0;
        rust_core_runtime_ns = 0;
        rust_store_callback_ns = 0;
        rust_store_callback_calls = 0;
        rust_jni_bytes_in = 0;
        rust_jni_bytes_out = 0;
    }

    public void record(TrieStoreMetricsDelta delta, RustFfiMetricsDelta ffiDelta) {
        store_get_ops += delta.getGetOps();
        store_put_ops += delta.getPutOps();
        store_delete_ops += delta.getDeleteOps();
        store_bytes_read += delta.getBytesRead();
        store_bytes_written_key += delta.getBytesWrittenKeys();
        store_bytes_written_value += delta.getBytesWrittenValues();
        rust_jni_calls += ffiDelta.getJniCalls();
        rust_ffi_decode_ns += ffiDelta.getFfiDecodeNanos();
        rust_ffi_encode_ns += ffiDelta.getFfiEncodeNanos();
        rust_core_runtime_ns += ffiDelta.getCoreRuntimeNanos();
        rust_store_callback_ns += ffiDelta.getStoreCallbackNanos();
        rust_store_callback_calls += ffiDelta.getStoreCallbackCalls();
        rust_jni_bytes_in += ffiDelta.getJniBytesIn();
        rust_jni_bytes_out += ffiDelta.getJniBytesOut();
    }
}
