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

import java.util.Locale;

public enum TrieEngineType {
    JAVA("java"),
    RUST("rust"),
    RUST_SHADOW("rust-shadow");

    private final String configName;

    TrieEngineType(String configName) {
        this.configName = configName;
    }

    public String getConfigName() {
        return configName;
    }

    public boolean usesRustBridge() {
        return this == RUST || this == RUST_SHADOW;
    }

    public static TrieEngineType fromConfig(String value) {
        if (value == null) {
            return JAVA;
        }

        String normalized = value.trim().toLowerCase(Locale.ROOT);
        for (TrieEngineType type : values()) {
            if (type.configName.equals(normalized)) {
                return type;
            }
        }

        throw new IllegalArgumentException("Unsupported unitrie engine: " + value);
    }
}
