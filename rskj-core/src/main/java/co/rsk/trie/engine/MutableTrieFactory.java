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

package co.rsk.trie.engine;

import co.rsk.db.MutableTrieImpl;
import co.rsk.trie.MutableTrie;
import co.rsk.trie.Trie;
import co.rsk.trie.TrieStore;
import co.rsk.trie.engine.rust.RustMutableTrie;
import co.rsk.trie.engine.rust.diagnostics.TrieDifferentialRecorder;

import javax.annotation.Nullable;
import java.util.Objects;

public class MutableTrieFactory {

    private final TrieEngineType engineType;
    private final boolean rustFailOnMismatch;
    @Nullable
    private final String rustLibraryPath;
    private final TrieDifferentialRecorder differentialRecorder;

    public MutableTrieFactory(
            TrieEngineType engineType,
            boolean rustFailOnMismatch,
            @Nullable String rustLibraryPath) {
        this(engineType, rustFailOnMismatch, rustLibraryPath, TrieDifferentialRecorder.noop());
    }

    public MutableTrieFactory(
            TrieEngineType engineType,
            boolean rustFailOnMismatch,
            @Nullable String rustLibraryPath,
            TrieDifferentialRecorder differentialRecorder) {
        this.engineType = Objects.requireNonNull(engineType, "engineType");
        this.rustFailOnMismatch = rustFailOnMismatch;
        this.rustLibraryPath = rustLibraryPath;
        this.differentialRecorder = Objects.requireNonNull(differentialRecorder, "differentialRecorder");
    }

    public static MutableTrieFactory javaDefault() {
        return new MutableTrieFactory(TrieEngineType.JAVA, true, null);
    }

    public MutableTrie create(TrieStore trieStore, Trie trie) {
        if (engineType == TrieEngineType.JAVA) {
            return new MutableTrieImpl(trieStore, trie);
        }

        return new RustMutableTrie(
                trieStore,
                trie,
                engineType,
                rustFailOnMismatch,
                rustLibraryPath,
                differentialRecorder
        );
    }

    public TrieEngineType getEngineType() {
        return engineType;
    }
}
