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

import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Measurement;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.annotations.OutputTimeUnit;
import org.openjdk.jmh.annotations.Timeout;
import org.openjdk.jmh.annotations.Warmup;

import java.util.concurrent.TimeUnit;

@BenchmarkMode({Mode.AverageTime})
@OutputTimeUnit(TimeUnit.MICROSECONDS)
@Warmup(iterations = 5)
@Measurement(iterations = 15)
@Timeout(time = 45)
public class TrieEngineBenchmark {

    @Benchmark
    public int putGetDeleteMix(TrieBenchmarkPlan plan) {
        byte[] key = plan.nextKey();
        byte[] value = plan.nextValue();
        plan.mutableTrie().put(key, value);
        byte[] loaded = plan.mutableTrie().get(key);
        plan.mutableTrie().deleteRecursive(key);
        return loaded == null ? 0 : loaded.length;
    }

    @Benchmark
    public int longValueHeavyPaths(TrieBenchmarkPlan plan) {
        byte[] key = plan.nextKey();
        byte[] value = plan.nextLongValue();
        plan.mutableTrie().put(key, value);
        byte[] loaded = plan.mutableTrie().get(key);
        return loaded == null ? 0 : loaded.length;
    }

    @Benchmark
    public int saveReloadCycle(TrieBenchmarkPlan plan) {
        plan.mutableTrie().put(plan.nextKey(), plan.nextValue());
        plan.saveAndReload();
        return plan.mutableTrie().getHash().getBytes().length;
    }

    @Benchmark
    public int accountStorageKeyIteration(TrieBenchmarkPlan plan) {
        return plan.iterateStorageKeys();
    }

    @Benchmark
    public int datasetDrivenMassiveUpload(TrieBenchmarkPlan plan) {
        plan.replayMassiveUploadDataset();
        return plan.mutableTrie().getHash().getBytes().length;
    }
}
