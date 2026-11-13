import co.rsk.bitcoinj.core.VarInt;

/** co.rsk.bitcoinj.core.VarInt (bitcoinj-thin 0.14.4-rsk-18) on the real class. */
public class VarIntHarness {
    /**
     * For every 64-bit value (read as unsigned): encode() has sizeOf(v) bytes, the size is
     * 1 / 3 / 5 / 9 by the Bitcoin CompactSize thresholds, the first byte is v, 0xFD, 0xFE or 0xFF,
     * and decoding gives back v with getOriginalSizeInBytes() == encoded length.
     */
    public static void roundTrip(long v) {
        VarInt vi = new VarInt(v);
        byte[] enc = vi.encode();
        int size = VarInt.sizeOf(v);
        assert enc.length == size;
        assert vi.getSizeInBytes() == size;
        int first = enc[0] & 0xFF;
        if (v >= 0 && v < 253) {
            assert size == 1 && first == v;
        } else if (v >= 253 && v <= 0xFFFFL) {
            assert size == 3 && first == 253;
        } else if (v > 0xFFFFL && v <= 0xFFFFFFFFL) {
            assert size == 5 && first == 254;
        } else {
            assert size == 9 && first == 255;
        }
        for (int i = 1; i < size; i++) {         // little-endian payload (TRIE-VARINT-01)
            assert (enc[i] & 0xFF) == ((v >>> (8 * (i - 1))) & 0xFF);
        }
        VarInt back = new VarInt(enc, 0);
        assert back.value == v;
        assert back.getOriginalSizeInBytes() == size;
    }

    /** Negative control: claims every value encodes in at most 5 bytes. */
    public static void roundTripNegative(long v) {
        assert new VarInt(v).encode().length <= 5;
    }
}
