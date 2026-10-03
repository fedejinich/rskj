import co.rsk.trie.PathEncoder;

/** PathEncoder (co/rsk/trie/PathEncoder.java) on the real class: bit-path encode/decode. */
public class PathEncoderHarness {
    /** Largest bit-path length checked (every length 0..MAX_BITS is checked). */
    static final int MAX_BITS = 64;

    /** Encoded length is ceil(n/8), bits packed MSB first, padding zero, decode(encode(p), n) == p. */
    public static void roundTrip() {
        for (int n = 0; n <= MAX_BITS; n++) {
            byte[] path = Nondet.bits(n);
            byte[] enc = PathEncoder.encode(path);
            assert enc.length == (n + 7) / 8;
            assert PathEncoder.calculateEncodedLength(n) == enc.length;
            for (int i = 0; i < enc.length * 8; i++) {
                assert ((enc[i / 8] >> (7 - i % 8)) & 1) == (i < n ? path[i] : 0);
            }
            byte[] dec = PathEncoder.decode(enc, n);
            assert dec.length == n;
            for (int i = 0; i < n; i++) {
                assert dec[i] == path[i];
            }
        }
    }

    /** encode(decode(e, n)) == e for every e of ceil(n/8) bytes whose padding bits are zero. */
    public static void decodeEncode() {
        for (int n = 0; n <= MAX_BITS; n++) {
            byte[] enc = Nondet.bytes((n + 7) / 8);
            boolean paddingZero = true;
            for (int i = n; i < enc.length * 8; i++) {
                paddingZero &= ((enc[i / 8] >> (7 - i % 8)) & 1) == 0;
            }
            byte[] dec = PathEncoder.decode(enc, n);
            for (int i = 0; i < n; i++) {
                assert dec[i] == 0 || dec[i] == 1;
            }
            byte[] again = PathEncoder.encode(dec);
            assert again.length == enc.length;
            boolean same = true;
            for (int i = 0; i < enc.length; i++) {
                same &= again[i] == enc[i];
            }
            assert same == paddingZero; // identity exactly on canonical (zero-padded) encodings
        }
    }

    /** Negative control for roundTrip: claims the first bit never survives the round trip as 1. */
    public static void roundTripNegative() {
        for (int n = 0; n <= MAX_BITS; n++) {
            byte[] path = Nondet.bits(n);
            byte[] dec = PathEncoder.decode(PathEncoder.encode(path), n);
            assert n == 0 || dec[0] == 0;
        }
    }

    /** Negative control for decodeEncode: claims every encoding is canonical. */
    public static void decodeEncodeNegative() {
        for (int n = 0; n <= MAX_BITS; n++) {
            byte[] enc = Nondet.bytes((n + 7) / 8);
            byte[] again = PathEncoder.encode(PathEncoder.decode(enc, n));
            for (int i = 0; i < enc.length; i++) {
                assert again[i] == enc[i];
            }
        }
    }
}
