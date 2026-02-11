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

package co.rsk.trie.engine.rust;

public class RustUnitriePerfCounters {
    private final long serializedNodes;
    private final long hashedNodes;
    private final long persistedNodes;
    private final long persistedValues;
    private final long cacheHits;
    private final long cacheMisses;
    private final long jniCalls;

    public RustUnitriePerfCounters(
            long serializedNodes,
            long hashedNodes,
            long persistedNodes,
            long persistedValues,
            long cacheHits,
            long cacheMisses,
            long jniCalls) {
        this.serializedNodes = serializedNodes;
        this.hashedNodes = hashedNodes;
        this.persistedNodes = persistedNodes;
        this.persistedValues = persistedValues;
        this.cacheHits = cacheHits;
        this.cacheMisses = cacheMisses;
        this.jniCalls = jniCalls;
    }

    public static RustUnitriePerfCounters empty() {
        return new RustUnitriePerfCounters(0, 0, 0, 0, 0, 0, 0);
    }

    public long getSerializedNodes() {
        return serializedNodes;
    }

    public long getHashedNodes() {
        return hashedNodes;
    }

    public long getPersistedNodes() {
        return persistedNodes;
    }

    public long getPersistedValues() {
        return persistedValues;
    }

    public long getCacheHits() {
        return cacheHits;
    }

    public long getCacheMisses() {
        return cacheMisses;
    }

    public long getJniCalls() {
        return jniCalls;
    }
}
