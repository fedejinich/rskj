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
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class RustTrieStoreAdapterTest {

    @Test
    void delegatesRawNodeAndValuePersistenceToTrieStore() {
        TrieStore trieStore = mock(TrieStore.class);
        RustTrieStoreAdapter adapter = new RustTrieStoreAdapter(trieStore);

        byte[] hash = new byte[] {1, 2, 3};
        byte[] node = new byte[] {4, 5};
        byte[] value = new byte[] {6, 7};

        adapter.saveRawNode(hash, node);
        adapter.saveRawValue(hash, value);

        verify(trieStore).saveRawNode(hash, node);
        verify(trieStore).saveRawValue(hash, value);
    }

    @Test
    void loadRawNodeUsesTrieStoreRetrieveValue() {
        TrieStore trieStore = mock(TrieStore.class);
        RustTrieStoreAdapter adapter = new RustTrieStoreAdapter(trieStore);

        byte[] hash = new byte[] {1, 2, 3};
        byte[] payload = new byte[] {9, 8, 7};
        when(trieStore.retrieveValue(hash)).thenReturn(payload);

        assertArrayEquals(payload, adapter.loadRawNode(hash));
        verify(trieStore).retrieveValue(hash);
    }
}
