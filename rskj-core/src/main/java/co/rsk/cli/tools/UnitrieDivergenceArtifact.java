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
package co.rsk.cli.tools;

import com.fasterxml.jackson.annotation.JsonInclude;

import javax.annotation.Nullable;
import java.util.List;

@JsonInclude(JsonInclude.Include.NON_NULL)
final class UnitrieDivergenceArtifact {
    private final String reason;
    private final String runId;
    private final int attemptIndex;
    private final BlockInfo block;
    private final RootInfo roots;
    private final TimingInfo timing;
    private final TxInfo tx;
    private final ConfigInfo config;
    private final List<String> suspectedSpecIds;
    private final String evidenceBundleId;
    private final String rustImpl;
    @Nullable
    private final JniCountersInfo jniCounters;
    @Nullable
    private final String corpusPath;
    @Nullable
    private final ExceptionInfo exception;

    UnitrieDivergenceArtifact(
            String reason,
            String runId,
            int attemptIndex,
            BlockInfo block,
            RootInfo roots,
            TimingInfo timing,
            TxInfo tx,
            ConfigInfo config,
            List<String> suspectedSpecIds,
            String evidenceBundleId,
            String rustImpl,
            @Nullable JniCountersInfo jniCounters,
            @Nullable String corpusPath,
            @Nullable ExceptionInfo exception) {
        this.reason = reason;
        this.runId = runId;
        this.attemptIndex = attemptIndex;
        this.block = block;
        this.roots = roots;
        this.timing = timing;
        this.tx = tx;
        this.config = config;
        this.suspectedSpecIds = suspectedSpecIds;
        this.evidenceBundleId = evidenceBundleId;
        this.rustImpl = rustImpl;
        this.jniCounters = jniCounters;
        this.corpusPath = corpusPath;
        this.exception = exception;
    }

    String getReason() {
        return reason;
    }

    String getRunId() {
        return runId;
    }

    int getAttemptIndex() {
        return attemptIndex;
    }

    BlockInfo getBlock() {
        return block;
    }

    RootInfo getRoots() {
        return roots;
    }

    TimingInfo getTiming() {
        return timing;
    }

    TxInfo getTx() {
        return tx;
    }

    ConfigInfo getConfig() {
        return config;
    }

    List<String> getSuspectedSpecIds() {
        return suspectedSpecIds;
    }

    String getEvidenceBundleId() {
        return evidenceBundleId;
    }

    String getRustImpl() {
        return rustImpl;
    }

    @Nullable
    JniCountersInfo getJniCounters() {
        return jniCounters;
    }

    @Nullable
    String getCorpusPath() {
        return corpusPath;
    }

    @Nullable
    ExceptionInfo getException() {
        return exception;
    }

    static final class BlockInfo {
        private final long number;
        private final String hash;
        private final String parentHash;
        private final String stateRoot;

        BlockInfo(long number, String hash, String parentHash, String stateRoot) {
            this.number = number;
            this.hash = hash;
            this.parentHash = parentHash;
            this.stateRoot = stateRoot;
        }

        long getNumber() {
            return number;
        }

        String getHash() {
            return hash;
        }

        String getParentHash() {
            return parentHash;
        }

        String getStateRoot() {
            return stateRoot;
        }
    }

    static final class RootInfo {
        @Nullable
        private final String javaRoot;
        @Nullable
        private final String rustRoot;

        RootInfo(@Nullable String javaRoot, @Nullable String rustRoot) {
            this.javaRoot = javaRoot;
            this.rustRoot = rustRoot;
        }

        @Nullable
        String getJavaRoot() {
            return javaRoot;
        }

        @Nullable
        String getRustRoot() {
            return rustRoot;
        }
    }

    static final class TimingInfo {
        private final double javaMsBlock;
        private final double rustMsBlock;
        private final double deltaMs;

        TimingInfo(double javaMsBlock, double rustMsBlock, double deltaMs) {
            this.javaMsBlock = javaMsBlock;
            this.rustMsBlock = rustMsBlock;
            this.deltaMs = deltaMs;
        }

        double getJavaMsBlock() {
            return javaMsBlock;
        }

        double getRustMsBlock() {
            return rustMsBlock;
        }

        double getDeltaMs() {
            return deltaMs;
        }
    }

    static final class TxInfo {
        private final int count;
        private final List<String> hashes;

        TxInfo(int count, List<String> hashes) {
            this.count = count;
            this.hashes = hashes;
        }

        int getCount() {
            return count;
        }

        List<String> getHashes() {
            return hashes;
        }
    }

    static final class ConfigInfo {
        private final String engine;
        private final boolean failFast;
        private final boolean failOnMismatch;
        @Nullable
        private final String rustLibraryPath;

        ConfigInfo(String engine, boolean failFast, boolean failOnMismatch, @Nullable String rustLibraryPath) {
            this.engine = engine;
            this.failFast = failFast;
            this.failOnMismatch = failOnMismatch;
            this.rustLibraryPath = rustLibraryPath;
        }

        String getEngine() {
            return engine;
        }

        boolean isFailFast() {
            return failFast;
        }

        boolean isFailOnMismatch() {
            return failOnMismatch;
        }

        @Nullable
        String getRustLibraryPath() {
            return rustLibraryPath;
        }
    }

    static final class JniCountersInfo {
        private final boolean available;
        private final long serializedNodes;
        private final long hashedNodes;
        private final long persistedNodes;
        private final long persistedValues;
        private final long cacheHits;
        private final long cacheMisses;
        private final long jniCalls;

        JniCountersInfo(
                boolean available,
                long serializedNodes,
                long hashedNodes,
                long persistedNodes,
                long persistedValues,
                long cacheHits,
                long cacheMisses,
                long jniCalls) {
            this.available = available;
            this.serializedNodes = serializedNodes;
            this.hashedNodes = hashedNodes;
            this.persistedNodes = persistedNodes;
            this.persistedValues = persistedValues;
            this.cacheHits = cacheHits;
            this.cacheMisses = cacheMisses;
            this.jniCalls = jniCalls;
        }

        boolean isAvailable() {
            return available;
        }

        long getSerializedNodes() {
            return serializedNodes;
        }

        long getHashedNodes() {
            return hashedNodes;
        }

        long getPersistedNodes() {
            return persistedNodes;
        }

        long getPersistedValues() {
            return persistedValues;
        }

        long getCacheHits() {
            return cacheHits;
        }

        long getCacheMisses() {
            return cacheMisses;
        }

        long getJniCalls() {
            return jniCalls;
        }
    }

    static final class ExceptionInfo {
        private final String className;
        private final String message;

        ExceptionInfo(String className, String message) {
            this.className = className;
            this.message = message;
        }

        String getClassName() {
            return className;
        }

        String getMessage() {
            return message;
        }
    }
}
