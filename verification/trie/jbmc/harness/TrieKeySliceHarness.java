import co.rsk.trie.PathEncoder;
import co.rsk.trie.TrieKeySlice;
import org.cprover.CProver;

/**
 * TrieKeySlice (co/rsk/trie/TrieKeySlice.java) against list semantics: a slice denotes the bit list
 * expandedKey[offset .. limit). Backs the Lean abstraction of slices as bit lists. Slices are built
 * with a nondet offset into a nondet backing array, so bits outside the window are arbitrary.
 */
public class TrieKeySliceHarness {
    /** Length of every backing array; windows [off, lim) range over all 0 <= off <= lim <= BACKING. */
    static final int BACKING = 12;

    /** A slice with a nondet window [off, lim) of a backing array of bits. */
    private static TrieKeySlice window(byte[] backing, int off, int lim) {
        CProver.assume(0 <= off && off <= lim && lim <= backing.length);
        return new TrieKeySlice(backing, off, lim);
    }

    /**
     * length/get/expand/encode denote the window; slice(from,to) is the sublist [from,to) and
     * throws IllegalArgumentException iff not 0 <= from <= to <= length. Indices are restricted to
     * [-2^30, 2^30] (see sliceIndexOverflow for what happens beyond).
     */
    public static void sliceSemantics(int off, int lim, int from, int to) {
        byte[] backing = Nondet.bits(BACKING);
        TrieKeySlice s = window(backing, off, lim);
        int n = lim - off;
        assert s.length() == n;
        byte[] ex = s.expand();
        assert ex.length == n;
        for (int i = 0; i < n; i++) {
            assert s.get(i) == backing[off + i] && ex[i] == backing[off + i];
        }
        byte[] enc = s.encode();
        byte[] direct = PathEncoder.encode(ex);
        assert enc.length == direct.length;
        for (int i = 0; i < enc.length; i++) {
            assert enc[i] == direct[i];
        }
        CProver.assume(from >= -(1 << 30) && from <= (1 << 30) && to >= -(1 << 30) && to <= (1 << 30));
        boolean valid = 0 <= from && from <= to && to <= n;
        TrieKeySlice sub;
        try {
            sub = s.slice(from, to);
        } catch (IllegalArgumentException e) {
            assert !valid;
            return;
        }
        assert valid;
        assert sub.length() == to - from;
        for (int i = 0; i < to - from; i++) {
            assert sub.get(i) == backing[off + from + i];
        }
    }

    /** commonPath is the longest common prefix. */
    public static void commonPathSemantics(int o1, int l1, int o2, int l2) {
        byte[] b1 = Nondet.bits(BACKING);
        byte[] b2 = Nondet.bits(BACKING);
        TrieKeySlice x = window(b1, o1, l1);
        TrieKeySlice y = window(b2, o2, l2);
        TrieKeySlice c = x.commonPath(y);
        int k = c.length();
        int min = Math.min(x.length(), y.length());
        assert 0 <= k && k <= min;
        for (int i = 0; i < k; i++) {
            assert c.get(i) == x.get(i) && x.get(i) == y.get(i);
        }
        assert k == min || x.get(k) != y.get(k);
    }

    /**
     * rebuildSharedPath(b, child) == this ++ [b] ++ child, whatever lies in the backing array beyond
     * this slice's limit, and it does not modify either input.
     */
    public static void rebuildSharedPathSemantics(int o1, int l1, int o2, int l2, boolean bit) {
        byte[] b1 = Nondet.bits(BACKING);
        byte[] b2 = Nondet.bits(BACKING);
        byte[] b1copy = b1.clone();
        byte[] b2copy = b2.clone();
        // SplitHarness fixes one length of x (LO) and of child (LO2). The limit is then written as
        // offset + length, so the length is a constant for symbolic execution rather than a symbolic
        // difference constrained by an assumption (which leaves every copy loop at its full bound).
        if (Nondet.HI3 == Nondet.LO3 + 1) o1 = Nondet.LO3; // SplitHarness: one offset of x
        CProver.assume(o1 >= Nondet.LO3 && o1 < Nondet.HI3);
        if (Nondet.HI == Nondet.LO + 1) l1 = o1 + Nondet.LO;
        if (Nondet.HI2 == Nondet.LO2 + 1) l2 = o2 + Nondet.LO2;
        TrieKeySlice x = window(b1, o1, l1);
        CProver.assume(l1 - o1 >= Nondet.LO && l1 - o1 < Nondet.HI);
        TrieKeySlice child = window(b2, o2, l2);
        CProver.assume(l2 - o2 >= Nondet.LO2 && l2 - o2 < Nondet.HI2);
        byte implicit = (byte) (bit ? 1 : 0);
        TrieKeySlice r = x.rebuildSharedPath(implicit, child);
        int n = x.length(), m = child.length();
        assert r.length() == n + 1 + m;
        for (int i = 0; i < n; i++) {
            assert r.get(i) == b1copy[o1 + i];
        }
        assert r.get(n) == implicit;
        for (int i = 0; i < m; i++) {
            assert r.get(n + 1 + i) == b2copy[o2 + i];
        }
        for (int i = 0; i < b1.length; i++) {
            assert b1[i] == b1copy[i];
        }
        for (int i = 0; i < b2.length; i++) {
            assert b2[i] == b2copy[i];
        }
    }

    /** leftPad(p) == p zeros ++ this, for p >= 0. */
    public static void leftPadSemantics(int o, int l, int p) {
        byte[] b = Nondet.bits(BACKING);
        TrieKeySlice x = window(b, o, l);
        CProver.assume(p >= 0 && p <= 16);
        TrieKeySlice r = x.leftPad(p);
        assert r.length() == p + x.length();
        for (int i = 0; i < p; i++) {
            assert r.get(i) == 0;
        }
        for (int i = 0; i < x.length(); i++) {
            assert r.get(p + i) == b[o + i];
        }
    }

    /** Largest key (bytes) for fromKeySemantics; every length 0..MAX_KEY_BYTES is checked. */
    static final int MAX_KEY_BYTES = 8;

    /** fromKey(k) is the MSB-first bit expansion of k (8 bits per byte); fromKey(null) is empty. */
    public static void fromKeySemantics() {
        assert TrieKeySlice.fromKey(null).length() == 0;
        for (int len = 0; len <= MAX_KEY_BYTES; len++) {
            byte[] key = Nondet.bytes(len);
            TrieKeySlice s = TrieKeySlice.fromKey(key);
            assert s.length() == 8 * len;
            for (int i = 0; i < 8 * len; i++) {
                assert s.get(i) == ((key[i / 8] >> (7 - i % 8)) & 1);
            }
        }
    }

    /** fromEncoded(src, off, n, ceil(n/8)) decodes the n bits of src[off..] MSB first. */
    public static void fromEncodedSemantics(int off, int n) {
        byte[] src = Nondet.bytes(4);
        CProver.assume(n >= 0 && n <= 32 && off >= 0 && off <= src.length);
        int enc = PathEncoder.calculateEncodedLength(n);
        CProver.assume(off + enc <= src.length);
        TrieKeySlice s = TrieKeySlice.fromEncoded(src, off, n, enc);
        assert s.length() == n;
        for (int i = 0; i < n; i++) {
            assert s.get(i) == ((src[off + i / 8] >> (7 - i % 8)) & 1);
        }
    }

    /** Negative control shared by the slice harnesses: claims commonPath is always shorter than both. */
    public static void commonPathNegative(int o1, int l1, int o2, int l2) {
        byte[] b1 = Nondet.bits(BACKING);
        byte[] b2 = Nondet.bits(BACKING);
        TrieKeySlice x = window(b1, o1, l1);
        TrieKeySlice y = window(b2, o2, l2);
        assert x.commonPath(y).length() < Math.min(x.length(), y.length());
    }

    /** Negative control: claims rebuildSharedPath always puts the implicit bit first. */
    public static void rebuildSharedPathNegative(int o1, int l1, int o2, int l2) {
        byte[] b1 = Nondet.bits(BACKING);
        byte[] b2 = Nondet.bits(BACKING);
        TrieKeySlice r = window(b1, o1, l1).rebuildSharedPath((byte) 1, window(b2, o2, l2));
        assert r.get(0) == 1;
    }

    /** Negative control: claims slice never throws. */
    public static void sliceNegative(int off, int lim, int from, int to) {
        byte[] backing = Nondet.bits(BACKING);
        TrieKeySlice s = window(backing, off, lim);
        CProver.assume(from >= -(1 << 30) && from <= (1 << 30) && to >= -(1 << 30) && to <= (1 << 30));
        try {
            s.slice(from, to);
        } catch (IllegalArgumentException e) {
            assert false;
        }
    }

    /**
     * Observation (expected FAILURE): with indices near Integer.MAX_VALUE, slice(from, to) on a slice
     * with offset > 0 does not throw although to > length, because offset + to overflows
     * (TrieKeySlice.java:64-67). Not reachable from the trie code, which only passes in-range indices.
     */
    public static void sliceIndexOverflow(int off, int lim, int from, int to) {
        byte[] backing = Nondet.bits(BACKING);
        TrieKeySlice s = window(backing, off, lim);
        boolean valid = 0 <= from && from <= to && to <= s.length();
        try {
            s.slice(from, to);
        } catch (IllegalArgumentException e) {
            return;
        }
        assert valid;
    }

    /** Negative control for leftPadSemantics: claims padding never changes the first bit. */
    public static void leftPadNegative(int o, int l, int p) {
        byte[] b = Nondet.bits(BACKING);
        TrieKeySlice x = window(b, o, l);
        CProver.assume(p >= 0 && p <= 16 && x.length() > 0);
        assert x.leftPad(p).get(0) == x.get(0);
    }

    /** Negative control for fromKeySemantics: claims the expansion of a key never starts with 1. */
    public static void fromKeyNegative() {
        for (int len = 1; len <= MAX_KEY_BYTES; len++) {
            assert TrieKeySlice.fromKey(Nondet.bytes(len)).get(0) == 0;
        }
    }

    /** Negative control for fromEncodedSemantics: claims the last decoded bit is always 0. */
    public static void fromEncodedNegative(int off, int n) {
        byte[] src = Nondet.bytes(4);
        CProver.assume(n >= 1 && n <= 32 && off >= 0 && off <= src.length);
        int enc = PathEncoder.calculateEncodedLength(n);
        CProver.assume(off + enc <= src.length);
        assert TrieKeySlice.fromEncoded(src, off, n, enc).get(n - 1) == 0;
    }
}
