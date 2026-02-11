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

import co.rsk.trie.Trie;
import co.rsk.trie.TrieStore;
import co.rsk.trie.engine.TrieEngineType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;

class RustMutableTrieTest {

    private static final String INVALID_NATIVE_LIBRARY = "/tmp/does-not-exist/libunitrie_rs_jni.so";

    @BeforeEach
    void resetBridgeState() {
        RustUnitrieBridge.resetForTesting();
    }

    @Test
    void rustShadowModeFallsBackToJavaWhenJniBridgeCannotBeLoaded() {
        TrieStore trieStore = mock(TrieStore.class);
        Trie trie = new Trie(trieStore);

        assertDoesNotThrow(() -> new RustMutableTrie(
                trieStore,
                trie,
                TrieEngineType.RUST_SHADOW,
                true,
                INVALID_NATIVE_LIBRARY
        ));
    }

    @Test
    void rustModeFailsFastWhenJniBridgeCannotBeLoaded() {
        TrieStore trieStore = mock(TrieStore.class);
        Trie trie = new Trie(trieStore);

        assertThrows(IllegalStateException.class, () -> new RustMutableTrie(
                trieStore,
                trie,
                TrieEngineType.RUST,
                true,
                INVALID_NATIVE_LIBRARY
        ));
    }
}
