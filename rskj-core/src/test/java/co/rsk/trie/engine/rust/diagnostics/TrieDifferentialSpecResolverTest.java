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
package co.rsk.trie.engine.rust.diagnostics;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class TrieDifferentialSpecResolverTest {

    @Test
    void resolvesSpecAndPhaseForKnownOperations() {
        assertEquals("SPEC-TRIE-PUT-SPLIT-COALESCE-001", TrieDifferentialSpecResolver.resolveSpecId("put", null));
        assertEquals("SPEC-TRIE-GET-FIND-001", TrieDifferentialSpecResolver.resolveSpecId("get", null));
        assertEquals("SPEC-STORAGE-KEYS-ITERATION-ORDER-001", TrieDifferentialSpecResolver.resolveSpecId("getStorageKeys", null));
        assertEquals("save", TrieDifferentialSpecResolver.resolvePhase("save"));
        assertEquals("read", TrieDifferentialSpecResolver.resolvePhase("getValueHash"));
        assertEquals("mutation", TrieDifferentialSpecResolver.resolvePhase("deleteRecursive"));
    }

    @Test
    void infersMismatchSpecFromMessage() {
        assertEquals(
                "SPEC-STORAGE-KEYS-ITERATION-ORDER-001",
                TrieDifferentialSpecResolver.resolveSpecId("mismatch", "unitrie-rs mismatch in getStorageKeys")
        );
        assertEquals(
                "SPEC-JNI-EXECUTION-STABILITY-001",
                TrieDifferentialSpecResolver.resolveSpecId("mismatch", "Rust execution failed with exception")
        );
        assertEquals(
                "SPEC-HASH-ROOT-PARITY-001",
                TrieDifferentialSpecResolver.resolveSpecId("mismatch", "state root mismatch")
        );
    }

    @Test
    void mapsSpecClassByPrefix() {
        assertEquals("trie", TrieDifferentialSpecResolver.resolveSpecClass("SPEC-TRIE-PUT-SPLIT-COALESCE-001"));
        assertEquals("persistence", TrieDifferentialSpecResolver.resolveSpecClass("SPEC-PERSISTENCE-SAVE-RAW-NODES-001"));
        assertEquals("hash", TrieDifferentialSpecResolver.resolveSpecClass("SPEC-HASH-ROOT-PARITY-001"));
        assertEquals("diagnostics", TrieDifferentialSpecResolver.resolveSpecClass("SPEC-UNKNOWN-001"));
    }
}
