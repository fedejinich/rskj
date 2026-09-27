import co.rsk.trie.Trie;
import co.rsk.trie.TrieKeySlice;
import org.ethereum.crypto.Keccak256Helper;

/** Bit-path conventions (RSKIP107) on the real co.rsk.trie classes. */
public class PathHarness {
    /** TRIE-PATH-01 rskip-reading (LSB first): fromKey([80]) would be 0000 0001. */
    public static void msbFirstRskip() {
        TrieKeySlice s = TrieKeySlice.fromKey(Nondet.b(0x80));
        assert s.get(0) == 0 && s.get(7) == 1;
    }

    /**
     * TRIE-PATH-02 (Java): for every pair of distinct one-byte keys diverging at bit d (from KEYS),
     * the root's shared path is the d common bits, the key whose bit d is 0 is the left child and the
     * other the right child, each with the remaining 7-d bits as shared path (the branch bit is not
     * stored); for {00, 80} the left child's shared path has 7 bits.
     */
    public static void branchBit() {
        Keccak256Helper.consistent = false;
        byte[][] K = Nondet.KEYS;
        for (byte[] a : K) {
            for (byte[] b : K) {
                if (a.length != 1 || b.length != 1 || a[0] == b[0]) {
                    continue;
                }
                int d = 0;
                while (((a[0] ^ b[0]) & (0x80 >> d)) == 0) {
                    d++;
                }
                byte[] va = Nondet.bytes(1), vb = Nondet.bytes(1);
                Trie t = new Trie().put(a, va).put(b, vb);
                assert t.getSharedPath().length() == d;
                boolean aLeft = (a[0] & (0x80 >> d)) == 0;
                Trie l = t.getLeft().getNode().get(), r = t.getRight().getNode().get();
                assert Nondet.same(l.getValue(), aLeft ? va : vb) && Nondet.same(r.getValue(), aLeft ? vb : va);
                assert l.getSharedPath().length() == 7 - d && r.getSharedPath().length() == 7 - d;
                byte[] lk = aLeft ? a : b;
                for (int i = 0; i < 7 - d; i++) {
                    assert l.getSharedPath().get(i) == ((lk[0] >> (6 - d - i)) & 1);
                }
            }
        }
    }

    /** TRIE-PATH-02 rskip-reading: the branch bit is part of the child's shared path (8 bits). */
    public static void branchBitRskip() {
        Keccak256Helper.consistent = false;
        Trie t = new Trie().put(Nondet.b(0x00), Nondet.bytes(1)).put(Nondet.b(0x80), Nondet.bytes(1));
        assert t.getLeft().getNode().get().getSharedPath().length() == 8;
    }
}
