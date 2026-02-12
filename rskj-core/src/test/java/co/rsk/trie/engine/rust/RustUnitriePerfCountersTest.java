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

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class RustUnitriePerfCountersTest {

    @Test
    void mapsLegacyRawCountersWithZeroFillForExtendedFields() {
        RustUnitriePerfCounters counters = RustUnitriePerfCounters.fromRawCounters(new long[] {
                1, 2, 3, 4, 5, 6, 7
        });

        assertEquals(1, counters.getSerializedNodes());
        assertEquals(7, counters.getJniCalls());
        assertEquals(0, counters.getFfiDecodeNanos());
        assertEquals(0, counters.getFfiEncodeNanos());
        assertEquals(0, counters.getCoreRuntimeNanos());
        assertEquals(0, counters.getStoreCallbackNanos());
        assertEquals(0, counters.getStoreCallbackCalls());
        assertEquals(0, counters.getJniBytesIn());
        assertEquals(0, counters.getJniBytesOut());
    }

    @Test
    void mapsExtendedRawCountersWhenPresent() {
        RustUnitriePerfCounters counters = RustUnitriePerfCounters.fromRawCounters(new long[] {
                1, 2, 3, 4, 5, 6, 7,
                8, 9, 10, 11, 12, 13, 14
        });

        assertEquals(8, counters.getFfiDecodeNanos());
        assertEquals(9, counters.getFfiEncodeNanos());
        assertEquals(10, counters.getCoreRuntimeNanos());
        assertEquals(11, counters.getStoreCallbackNanos());
        assertEquals(12, counters.getStoreCallbackCalls());
        assertEquals(13, counters.getJniBytesIn());
        assertEquals(14, counters.getJniBytesOut());
    }
}
