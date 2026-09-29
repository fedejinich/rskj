import co.rsk.trie.SharedPathSerializer;
import co.rsk.trie.TrieKeySlice;
import java.nio.ByteBuffer;
import org.cprover.CProver;

/** SharedPathSerializer (co/rsk/trie/SharedPathSerializer.java) on the real class. */
public class SharedPathSerializerHarness {
    private static final byte[] NO_PATH = new byte[0];

    /**
     * For every lshared in [1, Integer.MAX_VALUE]: serializeBytes writes a length prefix that
     * getPathBitsLength reads back exactly (value and number of bytes consumed), the prefix size is
     * calculateVarIntSize(lshared), it is one byte iff lshared is in 1..32 or 160..382, and the first
     * byte is lshared-1 (1..32), lshared-128 (160..382) or 255 followed by a VarInt (otherwise).
     */
    public static void lengthPrefixRoundTrip(int lshared) {
        CProver.assume(lshared >= 1);
        ByteBuffer out = ByteBuffer.allocate(16);
        SharedPathSerializer.serializeBytes(out, lshared, NO_PATH);
        int written = out.position();
        byte[] bytes = out.array();
        boolean oneByte = (lshared >= 1 && lshared <= 32) || (lshared >= 160 && lshared <= 382);
        assert (written == 1) == oneByte;
        assert written == SharedPathSerializer.calculateVarIntSize(lshared);
        int first = bytes[0] & 0xFF;
        if (lshared <= 32) {
            assert first == lshared - 1;
        } else if (lshared >= 160 && lshared <= 382) {
            assert first == lshared - 128;
        } else {
            assert first == 255;
        }
        ByteBuffer in = ByteBuffer.wrap(bytes);
        assert SharedPathSerializer.getPathBitsLength(in) == lshared;
        assert in.position() == written;
    }

    /** Negative control: claims the prefix is always a single byte. */
    public static void lengthPrefixRoundTripNegative(int lshared) {
        CProver.assume(lshared >= 1);
        ByteBuffer out = ByteBuffer.allocate(16);
        SharedPathSerializer.serializeBytes(out, lshared, NO_PATH);
        assert out.position() == 1;
    }

    /** Largest shared-path bit length checked by pathRoundTrip (every length 1..MAX_BITS). */
    static final int MAX_BITS = 40;

    /**
     * Full shared-path round trip through serializeInto/deserialize with symbolic path bits:
     * exactly getSerializedLength bytes are written and consumed, and the decoded slice has the
     * same bits. Checked for every length 1..MAX_BITS.
     */
    public static void pathRoundTrip() {
        for (int n = 1; n <= MAX_BITS; n++) {
            byte[] bits = Nondet.bits(n);
            TrieKeySlice path = new TrieKeySlice(bits, 0, n);
            SharedPathSerializer ser = new SharedPathSerializer(path);
            ByteBuffer out = ByteBuffer.allocate(ser.serializedLength());
            SharedPathSerializer.serializeInto(path, out);
            assert !out.hasRemaining();
            ByteBuffer in = ByteBuffer.wrap(out.array());
            TrieKeySlice back = SharedPathSerializer.deserialize(in, true);
            assert !in.hasRemaining();
            assert back.length() == n;
            for (int i = 0; i < n; i++) {
                assert back.get(i) == bits[i];
            }
        }
    }

    /** Negative control for pathRoundTrip: claims the last decoded bit is always 0. */
    public static void pathRoundTripNegative() {
        for (int n = 1; n <= MAX_BITS; n++) {
            byte[] bits = Nondet.bits(n);
            TrieKeySlice path = new TrieKeySlice(bits, 0, n);
            ByteBuffer out = ByteBuffer.allocate(new SharedPathSerializer(path).serializedLength());
            SharedPathSerializer.serializeInto(path, out);
            TrieKeySlice back = SharedPathSerializer.deserialize(ByteBuffer.wrap(out.array()), true);
            assert back.get(n - 1) == 0;
        }
    }

    static byte[] prefix(int l) {
        java.nio.ByteBuffer out = java.nio.ByteBuffer.allocate(16);
        SharedPathSerializer.serializeBytes(out, l, NO_PATH);
        return Nondet.slice(out.array(), 0, out.position());
    }

    /** TRIE-LSH-03 (Java): l = 33 -> ff21, 159 -> ff9f, 383 -> fffd7f01 (escape + VarInt(l)). */
    public static void escapeBytes() {
        assert Nondet.same(prefix(33), Nondet.b(0xff, 0x21));
        assert Nondet.same(prefix(159), Nondet.b(0xff, 0x9f));
        assert Nondet.same(prefix(383), Nondet.b(0xff, 0xfd, 0x7f, 0x01));
    }

    /** TRIE-LSH-03 rskip-reading (RSKIP107:104): the escape uses exactly 2 additional bytes. */
    public static void escapeBytesRskip() {
        assert prefix(33).length - 1 == 2 && prefix(383).length - 1 == 2;
    }
}
