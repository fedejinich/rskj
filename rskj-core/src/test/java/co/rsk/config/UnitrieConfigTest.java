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

package co.rsk.config;

import com.typesafe.config.ConfigFactory;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class UnitrieConfigTest {

    @Test
    void defaultUnitrieValuesAreConsensusSafe() {
        TestSystemProperties properties = new TestSystemProperties();

        assertEquals("java", properties.getUnitrieEngine());
        assertTrue(properties.isUnitrieRustFailOnMismatch());
        assertNull(properties.getUnitrieRustLibraryPath());
        assertEquals(50, properties.getUnitrieValidationRunDefaultBlockCount());
        assertEquals(500, properties.getUnitrieValidationRunDeepBlockCount());
    }

    @Test
    void readsUnitrieRustOptionsFromConfiguration() {
        TestSystemProperties properties = new TestSystemProperties(base ->
                ConfigFactory.parseString(
                        "blockchain.unitrie.engine = \"rust-shadow\"\n" +
                        "blockchain.unitrie.rust.failOnMismatch = false\n" +
                        "blockchain.unitrie.rust.libraryPath = \"/tmp/libunitrie_rs_jni.dylib\"\n" +
                        "blockchain.unitrie.validationRun.defaultBlockCount = 120\n" +
                        "blockchain.unitrie.validationRun.deepBlockCount = 1500\n"
                ).withFallback(base)
        );

        assertEquals("rust-shadow", properties.getUnitrieEngine());
        assertFalse(properties.isUnitrieRustFailOnMismatch());
        assertEquals("/tmp/libunitrie_rs_jni.dylib", properties.getUnitrieRustLibraryPath());
        assertEquals(120, properties.getUnitrieValidationRunDefaultBlockCount());
        assertEquals(1500, properties.getUnitrieValidationRunDeepBlockCount());
    }
}
