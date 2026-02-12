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

import javax.annotation.Nullable;
import java.util.Locale;

public final class TrieDifferentialSpecResolver {

    public static final String UNKNOWN_SPEC_ID = "SPEC-TRIE-UNCLASSIFIED-001";

    private TrieDifferentialSpecResolver() {
    }

    public static String resolveSpecId(String operation, @Nullable String mismatchMessage) {
        switch (operation) {
            case "put":
            case "delete":
                return "SPEC-TRIE-PUT-SPLIT-COALESCE-001";
            case "get":
                return "SPEC-TRIE-GET-FIND-001";
            case "deleteRecursive":
                return "SPEC-TRIE-DELETE-RECURSIVE-PREFIX-001";
            case "collectKeys":
                return "SPEC-TRIE-COLLECT-KEYS-ITERATION-001";
            case "getValueLength":
            case "getValueHash":
                return "SPEC-TRIE-VALUE-LENGTH-HASH-001";
            case "getStorageKeys":
                return "SPEC-STORAGE-KEYS-ITERATION-ORDER-001";
            case "save":
                return "SPEC-PERSISTENCE-SAVE-RAW-NODES-001";
            case "probeFinalStateRoot":
                return "SPEC-HASH-ROOT-PARITY-001";
            case "probeException":
                return "SPEC-JNI-EXECUTION-STABILITY-001";
            case "mismatch":
                return inferSpecFromMismatchMessage(mismatchMessage);
            default:
                return UNKNOWN_SPEC_ID;
        }
    }

    public static String resolveSpecClass(String specId) {
        if (specId.startsWith("SPEC-TRIE-")) {
            return "trie";
        }

        if (specId.startsWith("SPEC-CODEC-RSKIP107-")) {
            return "codec-rskip107";
        }

        if (specId.startsWith("SPEC-CODEC-ORCHID-")) {
            return "codec-orchid";
        }

        if (specId.startsWith("SPEC-STORAGE-KEYS-")) {
            return "storage-keys";
        }

        if (specId.startsWith("SPEC-PERSISTENCE-")) {
            return "persistence";
        }

        if (specId.startsWith("SPEC-HASH-")) {
            return "hash";
        }

        if (specId.startsWith("SPEC-JNI-")) {
            return "jni";
        }

        return "diagnostics";
    }

    public static String resolvePhase(String operation) {
        switch (operation) {
            case "put":
            case "delete":
            case "deleteRecursive":
            case "mismatch":
                return "mutation";
            case "get":
            case "getValueLength":
            case "getValueHash":
            case "collectKeys":
            case "getStorageKeys":
                return "read";
            case "save":
                return "save";
            case "probeFinalStateRoot":
            case "probeException":
                return "reload";
            default:
                return "mutation";
        }
    }

    private static String inferSpecFromMismatchMessage(@Nullable String mismatchMessage) {
        if (mismatchMessage == null || mismatchMessage.isBlank()) {
            return "SPEC-HASH-ROOT-PARITY-001";
        }

        String normalized = mismatchMessage.toLowerCase(Locale.ROOT);
        if (normalized.contains("storage")) {
            return "SPEC-STORAGE-KEYS-ITERATION-ORDER-001";
        }

        if (normalized.contains("valuelength") || normalized.contains("valuehash")) {
            return "SPEC-TRIE-VALUE-LENGTH-HASH-001";
        }

        if (normalized.contains("collectkeys")) {
            return "SPEC-TRIE-COLLECT-KEYS-ITERATION-001";
        }

        if (normalized.contains("deleterecursive")) {
            return "SPEC-TRIE-DELETE-RECURSIVE-PREFIX-001";
        }

        if (normalized.contains("save") || normalized.contains("persist")) {
            return "SPEC-PERSISTENCE-SAVE-RAW-NODES-001";
        }

        if (normalized.contains("exception") || normalized.contains("jni")) {
            return "SPEC-JNI-EXECUTION-STABILITY-001";
        }

        if (normalized.contains("root")) {
            return "SPEC-HASH-ROOT-PARITY-001";
        }

        return UNKNOWN_SPEC_ID;
    }
}
