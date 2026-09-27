import org.cprover.CProver;

/**
 * Symbolic inputs for the harnesses. Arrays get a concrete length and nondet contents: harnesses
 * enumerate every length up to their bound in a loop, which JBMC handles far better than a
 * symbolic array length.
 */
final class Nondet {
    private Nondet() { }

    static byte[] bytes(int n) {
        // concrete length, element-wise nondet: a whole-array nondet (CProver.nondetWithoutNull)
        // leaves the length symbolic for symbolic execution even after assume(length == n), and in
        // the key-mapping harnesses its array-theory encoding exhausted the 6 GB limit in the solver
        // (key-strip-leading-zeroes part00: memory stop at 90 s whole-array, SUCCESS in 15 s here)
        byte[] a = new byte[n];
        for (int i = 0; i < n; i++) {
            a[i] = CProver.nondetByte();
        }
        return a;
    }

    /** n nondet bits, each 0 or 1 (the expanded-key alphabet). */
    static byte[] bits(int n) {
        byte[] a = new byte[n];
        for (int i = 0; i < n; i++) {
            a[i] = CProver.nondetBoolean() ? (byte) 1 : (byte) 0;
        }
        return a;
    }

    static int intIn(int lo, int hi) {
        int x = CProver.nondetInt();
        CProver.assume(lo <= x && x <= hi);
        return x;
    }

    /**
     * Concrete key universe for multi-key trie harnesses (see TrieOpsHarness for why keys are
     * concrete). Relative to each other these keys realise: the empty key; one-byte keys diverging at
     * bit 0 (00/80, 7f/ff), bit 7 (00/01, fe/ff) and bit 3 (00/10); a key and its one-byte
     * extensions (00 < 00 00, 00 < 00 80, ff < ff 7f); two-byte keys sharing their first byte and
     * diverging at bit 8 or 15. Each divergence occurs with the other key on the left and on the right.
     */
    /**
     * Range of first keys (indices into KEYS) that multi-key harnesses enumerate; the default is all
     * of them. SplitHarness sets a single index to split a heavy check into one entry per first key
     * (static int assignments are concrete for JBMC); the union of the split entries is the full check.
     */
    static int LO = 0;
    static int HI = Integer.MAX_VALUE;
    /** Second split dimension, same convention (used by rebuildSharedPathSemantics: child length). */
    static int LO2 = 0;
    static int HI2 = Integer.MAX_VALUE;
    /** Third split dimension (rebuildSharedPathSemantics: offset of the prefix slice). */
    static int LO3 = 0;
    static int HI3 = Integer.MAX_VALUE;

    /** Whether a harness's own second-level index j is in this split part: always unless LO2/HI2 are
     *  set. Used as a filter inside stepped or negative-start loops, so their enumeration is unchanged. */
    static boolean in2(int j) {
        return HI2 == Integer.MAX_VALUE || (LO2 <= j && j < HI2);
    }

    static final byte[][] KEYS = {
        {}, {0x00}, {(byte) 0x80}, {0x01}, {0x10}, {(byte) 0xff}, {0x7f}, {(byte) 0xfe},
        {0x00, 0x00}, {0x00, (byte) 0x80}, {0x00, 0x01}, {(byte) 0xff, 0x7f},
    };

    /**
     * Value lengths used by the trie harnesses, each enumerated concretely (a symbolic length would
     * make every long-value branch symbolic): 1 byte, 32 bytes (longest inline value) and 33 bytes
     * (shortest long value, stored by hash, RSKIP107 hasLongVal).
     */
    static final int[] VALUE_LENGTHS = {1, 32, 33};

    static final int LONG_VALUE = 33;

    static boolean same(byte[] a, byte[] b) {
        if (a == null || b == null) {
            return a == b;
        }
        if (a.length != b.length) {
            return false;
        }
        for (int i = 0; i < a.length; i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }

    /** Concrete byte array from int literals. */
    static byte[] b(int... v) {
        byte[] a = new byte[v.length];
        for (int i = 0; i < v.length; i++) {
            a[i] = (byte) v[i];
        }
        return a;
    }

    /** n copies of byte x. */
    static byte[] rep(int n, int x) {
        byte[] a = new byte[n];
        for (int i = 0; i < n; i++) {
            a[i] = (byte) x;
        }
        return a;
    }

    static byte[] cat(byte[]... parts) {
        int n = 0;
        for (byte[] p : parts) {
            n += p.length;
        }
        byte[] r = new byte[n];
        int k = 0;
        for (byte[] p : parts) {
            for (int i = 0; i < p.length; i++) {
                r[k++] = p[i];
            }
        }
        return r;
    }

    /** a[from .. from+len) equals e. */
    static boolean at(byte[] a, int from, byte[] e) {
        if (from < 0 || from + e.length > a.length) {
            return false;
        }
        for (int i = 0; i < e.length; i++) {
            if (a[from + i] != e[i]) {
                return false;
            }
        }
        return true;
    }

    static byte[] slice(byte[] a, int from, int to) {
        byte[] r = new byte[to - from];
        for (int i = from; i < to; i++) {
            r[i - from] = a[i];
        }
        return r;
    }
}
