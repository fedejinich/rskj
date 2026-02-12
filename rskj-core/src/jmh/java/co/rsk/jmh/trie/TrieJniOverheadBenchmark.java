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

package co.rsk.jmh.trie;

import co.rsk.trie.engine.rust.RustUnitrieBridge;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Level;
import org.openjdk.jmh.annotations.Measurement;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.annotations.OutputTimeUnit;
import org.openjdk.jmh.annotations.Param;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.Setup;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.annotations.Timeout;
import org.openjdk.jmh.annotations.Warmup;

import java.util.concurrent.TimeUnit;

@BenchmarkMode({Mode.AverageTime, Mode.SampleTime, Mode.Throughput})
@OutputTimeUnit(TimeUnit.MICROSECONDS)
@Warmup(iterations = 5)
@Measurement(iterations = 15)
@Timeout(time = 45)
public class TrieJniOverheadBenchmark {

    @Benchmark
    public long jniNoop(JniPlan plan) {
        return plan.bridge.benchmarkNoop(plan.iterations);
    }

    @Benchmark
    public long jniRoundtrip32B(JniPlan plan) {
        return plan.bridge.benchmarkRoundtrip(plan.payload32, plan.iterations);
    }

    @Benchmark
    public long jniRoundtrip256B(JniPlan plan) {
        return plan.bridge.benchmarkRoundtrip(plan.payload256, plan.iterations);
    }

    @Benchmark
    public long jniRoundtrip4KB(JniPlan plan) {
        return plan.bridge.benchmarkRoundtrip(plan.payload4096, plan.iterations);
    }

    @State(Scope.Thread)
    public static class JniPlan {

        // Kept for compatibility with the shared benchmark runner parameters.
        @Param({"rust"})
        public String engine;

        // Kept for compatibility with the shared benchmark runner parameters.
        @Param({"true"})
        public boolean failOnMismatch;

        @Param({""})
        public String rustLibraryPath;

        // Kept for compatibility with the shared benchmark runner parameters.
        @Param({"next"})
        public String rustImplementation;

        @Param({"1024"})
        public int iterations;

        private RustUnitrieBridge bridge;
        private byte[] payload32;
        private byte[] payload256;
        private byte[] payload4096;

        @Setup(Level.Trial)
        public void setup() {
            String configuredPath = rustLibraryPath == null || rustLibraryPath.isBlank()
                    ? null
                    : rustLibraryPath;
            bridge = RustUnitrieBridge.load(configuredPath);
            if (!bridge.isAvailable()) {
                throw new IllegalStateException("unitrie-rs JNI bridge is unavailable for JNI micro benchmark");
            }

            payload32 = new byte[32];
            payload256 = new byte[256];
            payload4096 = new byte[4096];
            for (int i = 0; i < payload32.length; i++) {
                payload32[i] = (byte) (i & 0xff);
            }
            for (int i = 0; i < payload256.length; i++) {
                payload256[i] = (byte) (i & 0xff);
            }
            for (int i = 0; i < payload4096.length; i++) {
                payload4096[i] = (byte) (i & 0xff);
            }
        }
    }
}
