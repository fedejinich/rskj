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

import java.util.Locale;

public enum RustUnitrieImplementation {
    LEGACY_V1("legacy-v1"),
    NEXT("next");

    private final String configName;

    RustUnitrieImplementation(String configName) {
        this.configName = configName;
    }

    public String getConfigName() {
        return configName;
    }

    public static RustUnitrieImplementation fromConfig(String value) {
        if (value == null) {
            return LEGACY_V1;
        }

        String normalized = value.trim().toLowerCase(Locale.ROOT);
        for (RustUnitrieImplementation implementation : values()) {
            if (implementation.configName.equals(normalized)) {
                return implementation;
            }
        }

        throw new IllegalArgumentException("Unsupported unitrie rust implementation: " + value);
    }
}
