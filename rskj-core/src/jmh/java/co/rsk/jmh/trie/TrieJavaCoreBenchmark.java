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

import co.rsk.db.MutableTrieImpl;
import co.rsk.jmh.trie.core.TrieCoreWorkloadCorpus;
import co.rsk.trie.MutableTrie;
import co.rsk.trie.Trie;
import co.rsk.trie.TrieStore;
import co.rsk.trie.TrieStoreImpl;
import org.ethereum.datasource.HashMapDB;
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
public class TrieJavaCoreBenchmark {

    @Benchmark
    public int putGetDeleteMix(CorePlan plan) {
        return plan.executeWorkload("putGetDeleteMix");
    }

    @Benchmark
    public int longValueHeavyPaths(CorePlan plan) {
        return plan.executeWorkload("longValueHeavyPaths");
    }

    @Benchmark
    public int saveReloadCycle(CorePlan plan) {
        return plan.executeWorkload("saveReloadCycle");
    }

    @Benchmark
    public int accountStorageKeyIteration(CorePlan plan) {
        return plan.executeWorkload("accountStorageKeyIteration");
    }

    @Benchmark
    public int datasetDrivenMassiveUpload(CorePlan plan) {
        return plan.executeWorkload("datasetDrivenMassiveUpload");
    }

    @State(Scope.Thread)
    public static class CorePlan {

        // Kept for compatibility with the shared benchmark runner parameters.
        @Param({"java"})
        public String engine;

        // Kept for compatibility with the shared benchmark runner parameters.
        @Param({"true"})
        public boolean failOnMismatch;

        // Kept for compatibility with the shared benchmark runner parameters.
        @Param({""})
        public String rustLibraryPath;

        // Kept for compatibility with the shared benchmark runner parameters.
        @Param({"next"})
        public String rustImplementation;

        private TrieCoreWorkloadCorpus corpus;

        @Setup(Level.Trial)
        public void setupTrial() {
            corpus = TrieCoreWorkloadCorpus.loadDefault();
        }

        int executeWorkload(String workloadName) {
            TrieCoreWorkloadCorpus.Workload selectedWorkload = corpus.workload(workloadName);
            TrieStore trieStore = new TrieStoreImpl(new HashMapDB());
            MutableTrie mutableTrie = new MutableTrieImpl(trieStore, new Trie(trieStore));
            int checksum = 0;

            try {
                for (int repeat = 0; repeat < selectedWorkload.repeat(); repeat++) {
                    for (TrieCoreWorkloadCorpus.Operation operation : selectedWorkload.operations()) {
                        switch (operation.type()) {
                            case PUT -> {
                                mutableTrie.put(operation.key(), operation.value());
                                checksum ^= operation.value().length;
                            }
                            case GET -> {
                                byte[] value = mutableTrie.get(operation.key());
                                checksum ^= value == null ? 0 : value.length;
                            }
                            case DELETE -> mutableTrie.put(operation.key(), null);
                            case DELETE_RECURSIVE -> mutableTrie.deleteRecursive(operation.key());
                            case GET_VALUE_LENGTH -> checksum ^= mutableTrie.getValueLength(operation.key()).intValue();
                            case GET_VALUE_HASH -> checksum ^= mutableTrie.getValueHash(operation.key())
                                    .map(hash -> hash.getBytes().length)
                                    .orElse(0);
                            case COLLECT_KEYS -> checksum ^= mutableTrie.collectKeys(operation.size()).size();
                            case SAVE -> mutableTrie.save();
                            case SAVE_RELOAD -> {
                                mutableTrie.save();
                                byte[] rootHash = mutableTrie.getHash().getBytes();
                                Trie root = trieStore.retrieve(rootHash)
                                        .orElseThrow(() -> new IllegalStateException("Saved root not found during java core benchmark"));
                                mutableTrie = new MutableTrieImpl(trieStore, root);
                                checksum ^= rootHash.length;
                            }
                            case ROOT_HASH -> checksum ^= mutableTrie.getHash().getBytes().length;
                            default -> throw new IllegalStateException("Unsupported operation type: " + operation.type());
                        }
                    }
                }

                return checksum;
            } finally {
                trieStore.dispose();
            }
        }
    }
}
