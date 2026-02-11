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

import co.rsk.trie.TrieStore;

import javax.annotation.Nullable;
import java.util.Objects;

/**
 * JNI-facing adapter that exposes raw trie persistence operations to Rust.
 */
public class RustTrieStoreAdapter {

    private final TrieStore trieStore;

    public RustTrieStoreAdapter(TrieStore trieStore) {
        this.trieStore = Objects.requireNonNull(trieStore, "trieStore");
    }

    @Nullable
    public byte[] loadRawNode(byte[] hash) {
        return trieStore.retrieveValue(hash);
    }

    public void saveRawNode(byte[] hash, byte[] serializedNode) {
        trieStore.saveRawNode(hash, serializedNode);
    }

    public void saveRawValue(byte[] hash, byte[] value) {
        trieStore.saveRawValue(hash, value);
    }
}
