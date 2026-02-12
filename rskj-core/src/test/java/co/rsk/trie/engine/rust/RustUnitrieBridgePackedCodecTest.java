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

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class RustUnitrieBridgePackedCodecTest {

    @Test
    void decodeStorageKeysPackedRoundTrip() {
        List<byte[]> original = List.of(
                new byte[] {0x01},
                new byte[] {(byte) 0xaa, (byte) 0xbb},
                repeated((byte) 0x10, 260)
        );

        byte[] packed = encodePacked(original);
        List<byte[]> decoded = RustUnitrieBridge.decodeStorageKeysPacked(packed);

        assertEquals(original.size(), decoded.size());
        for (int index = 0; index < original.size(); index++) {
            assertArrayEquals(original.get(index), decoded.get(index));
        }
    }

    @Test
    void decodeStorageKeysPackedRejectsTruncatedPayload() {
        List<byte[]> original = List.of(new byte[] {0x01, 0x02, 0x03});
        byte[] packed = encodePacked(original);
        byte[] truncated = new byte[packed.length - 1];
        System.arraycopy(packed, 0, truncated, 0, truncated.length);

        IllegalStateException error = assertThrows(
                IllegalStateException.class,
                () -> RustUnitrieBridge.decodeStorageKeysPacked(truncated)
        );

        assertTrue(error.getMessage().contains("truncated"));
    }

    @Test
    void decodeStorageKeysPackedRejectsTrailingBytes() {
        List<byte[]> original = List.of(new byte[] {0x01, 0x02});
        byte[] packed = encodePacked(original);
        byte[] withTrailing = new byte[packed.length + 1];
        System.arraycopy(packed, 0, withTrailing, 0, packed.length);
        withTrailing[withTrailing.length - 1] = 0x55;

        IllegalStateException error = assertThrows(
                IllegalStateException.class,
                () -> RustUnitrieBridge.decodeStorageKeysPacked(withTrailing)
        );

        assertTrue(error.getMessage().contains("trailing"));
    }

    @Test
    void decodeStorageKeysPackedTreatsNullAndEmptyAsNoKeys() {
        assertTrue(RustUnitrieBridge.decodeStorageKeysPacked(null).isEmpty());
        assertTrue(RustUnitrieBridge.decodeStorageKeysPacked(new byte[0]).isEmpty());
    }

    private static byte[] repeated(byte value, int len) {
        byte[] output = new byte[len];
        for (int index = 0; index < output.length; index++) {
            output[index] = value;
        }
        return output;
    }

    private static byte[] encodePacked(List<byte[]> values) {
        ArrayList<Byte> bytes = new ArrayList<>();
        encodeVarInt(values.size(), bytes);
        for (byte[] value : values) {
            encodeVarInt(value.length, bytes);
            for (byte b : value) {
                bytes.add(b);
            }
        }

        byte[] output = new byte[bytes.size()];
        for (int index = 0; index < bytes.size(); index++) {
            output[index] = bytes.get(index);
        }
        return output;
    }

    private static void encodeVarInt(long value, ArrayList<Byte> out) {
        if (value < 0xfd) {
            out.add((byte) value);
            return;
        }

        if (value <= 0xffff) {
            out.add((byte) 0xfd);
            appendLE(value, 2, out);
            return;
        }

        if (value <= 0xffff_ffffL) {
            out.add((byte) 0xfe);
            appendLE(value, 4, out);
            return;
        }

        out.add((byte) 0xff);
        appendLE(value, 8, out);
    }

    private static void appendLE(long value, int size, ArrayList<Byte> out) {
        for (int shift = 0; shift < size; shift++) {
            out.add((byte) ((value >> (shift * 8)) & 0xff));
        }
    }
}
