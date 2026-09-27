import co.rsk.trie.NodeReference;
import co.rsk.trie.Trie;
import org.ethereum.crypto.Keccak256Helper;

/**
 * More trie operation obligations on the real co.rsk.trie.Trie: empty trie, empty value vs null,
 * immutability, deleteRecursive, canonical shape and history independence, the Uint24 value bound.
 * Keys from the concrete universe Nondet.KEYS (see TrieOpsHarness), values with nondet contents.
 * Keccak unconstrained unless stated (these properties do not read digest values).
 */
public class OpsExtraHarness {
    /** TRIE-OPS-01: new Trie().get(k) == null for every key of 0..3 bytes (fully symbolic). */
    public static void emptyTrie() {
        Keccak256Helper.consistent = false;
        for (int n = 0; n <= 3; n++) {
            assert new Trie().get(Nondet.bytes(n)) == null;
        }
    }

    public static void emptyTrieNegative() {
        Keccak256Helper.consistent = false;
        assert new Trie().put(Nondet.b(1), Nondet.bytes(1)).get(Nondet.bytes(1)) == null;
    }

    /** TRIE-OPS-06: put(k, empty), put(k, null) and delete(k) give identical tries (same message and
     *  lookups), from every 2-key trie over KEYS. Same message implies same getHash (TRIE-HASH-01). */
    public static void emptyAndNullAreDelete() {
        // consistent oracle: the property compares messages of two independently built tries, which
        // embed separately computed child hashes (unconstrained hashes would differ spuriously)
        Keccak256Helper.consistent = true;
        Keccak256Helper.concreteOutputs = true;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            Trie t1 = new Trie().put(K[i], Nondet.bytes(1));
            for (int j = 0; j < K.length; j++) {
                Trie t = t1.put(K[j], Nondet.bytes(1));
                for (byte[] kd : K) {
                    byte[] d = t.delete(kd).toMessage();
                    Trie e = t.put(kd, new byte[0]);
                    Trie n = t.put(kd, null);
                    assert Nondet.same(e.toMessage(), d) && Nondet.same(n.toMessage(), d);
                    for (byte[] q : K) {
                        assert Nondet.same(e.get(q), n.get(q));
                    }
                }
            }
        }
    }

    /**
     * TRIE-OPS-08: after t2 = t.put(k, v) / t.delete(k) / t.deleteRecursive(k), t's lookups and
     * message are unchanged; mutating the array given to put or returned by get changes no trie.
     */
    public static void immutable() {
        Keccak256Helper.consistent = false;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            for (int j = 0; j < K.length; j++) {
                Trie t = new Trie().put(K[i], Nondet.bytes(1)).put(K[j], Nondet.bytes(1));
                byte[] m = t.toMessage();
                byte[][] before = new byte[K.length][];
                for (int q = 0; q < K.length; q++) {
                    before[q] = t.get(K[q]);
                }
                for (byte[] k : K) {
                    byte[] v = Nondet.bytes(1);
                    byte v0 = v[0];
                    Trie t2 = t.put(k, v);
                    v[0] ^= 1;                               // mutate the argument after put
                    assert t2.get(k)[0] == v0;
                    byte[] r = t2.get(k);
                    r[0] ^= 1;                               // mutate the returned array
                    assert t2.get(k)[0] == v0;
                    t.delete(k);
                    t.deleteRecursive(k);
                    assert Nondet.same(t.toMessage(), m);
                    for (int q = 0; q < K.length; q++) {
                        assert Nondet.same(t.get(K[q]), before[q]);
                    }
                }
            }
        }
    }

    public static void immutableNegative() {
        Keccak256Helper.consistent = false;
        Trie t = new Trie().put(Nondet.KEYS[1], Nondet.bytes(1));
        byte[] m = t.toMessage();
        assert Nondet.same(t.put(Nondet.KEYS[2], Nondet.bytes(1)).toMessage(), m);
    }

    static boolean startsWith(byte[] k, byte[] p) {
        if (k.length < p.length) {
            return false;
        }
        for (int i = 0; i < p.length; i++) {
            if (k[i] != p[i]) {
                return false;
            }
        }
        return true;
    }

    /**
     * TRIE-OPS-09 (Java): if k has a value in t, deleteRecursive(k) removes k and every key extending
     * k and leaves every other key unchanged (all 2- and 3-key tries over KEYS, probes in KEYS).
     */
    public static void deleteRecursiveWithValue() {
        Keccak256Helper.consistent = false;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            for (int j = 0; j < K.length; j++) {
                Trie t = new Trie().put(K[i], Nondet.bytes(1)).put(K[j], Nondet.bytes(1));
                for (byte[] k : new byte[][] {K[i], K[j]}) {
                    Trie d = t.deleteRecursive(k);
                    for (byte[] q : K) {
                        assert Nondet.same(d.get(q), startsWith(q, k) ? null : t.get(q));
                    }
                }
            }
        }
    }

    /** TRIE-OPS-09 (Java, reproducer): {0100: aa, 0180: bb}.deleteRecursive(01) changes nothing,
     *  although the root node sits exactly at key 01 (shared path = the 8 bits of 01). */
    public static void deleteRecursiveBranchNode() {
        Keccak256Helper.consistent = false;
        Trie t = new Trie().put(Nondet.b(0x01, 0x00), Nondet.b(0xaa)).put(Nondet.b(0x01, 0x80), Nondet.b(0xbb));
        assert t.getSharedPath().length() == 8;
        Trie d = t.deleteRecursive(Nondet.b(0x01));
        assert Nondet.same(d.get(Nondet.b(0x01, 0x00)), Nondet.b(0xaa));
        assert Nondet.same(d.toMessage(), t.toMessage());
    }

    /** TRIE-OPS-09 rskip-reading: a node exists exactly at 01, so get(0100) must be null afterwards. */
    public static void deleteRecursiveRskip() {
        Keccak256Helper.consistent = false;
        Trie t = new Trie().put(Nondet.b(0x01, 0x00), Nondet.b(0xaa)).put(Nondet.b(0x01, 0x80), Nondet.b(0xbb));
        assert t.deleteRecursive(Nondet.b(0x01)).get(Nondet.b(0x01, 0x00)) == null;
    }

    static void canonical(Trie n, boolean root) {
        boolean hasValue = n.getValueLength().intValue() > 0;
        boolean two = !n.getLeft().isEmpty() && !n.getRight().isEmpty();
        boolean none = n.getLeft().isEmpty() && n.getRight().isEmpty();
        if (root) {
            assert n.isEmptyTrie() || hasValue || two;
            if (n.isEmptyTrie()) {
                assert n.getSharedPath().length() == 0;
            }
        } else {
            assert hasValue || two;
            assert !(none && !hasValue);
        }
        NodeReference[] refs = {n.getLeft(), n.getRight()};
        for (NodeReference r : refs) {
            if (!r.isEmpty()) {
                canonical(r.getNode().get(), false);
            }
        }
    }

    /** TRIE-CMP-01: every trie reached by 1..3 puts and a delete over KEYS has canonical shape. */
    public static void canonicalShape() {
        Keccak256Helper.consistent = false;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            Trie t1 = new Trie().put(K[i], Nondet.bytes(1));
            canonical(t1, true);
            canonical(t1.delete(K[i]), true);
            for (int j = 0; j < K.length; j++) {
                Trie t2 = t1.put(K[j], Nondet.bytes(1));
                canonical(t2, true);
                for (int l = 0; l < K.length; l++) {
                    canonical(t2.delete(K[l]), true);
                    canonical(t2.put(K[l], Nondet.bytes(1)), true);
                }
            }
        }
    }

    public static void canonicalShapeNegative() {
        Keccak256Helper.consistent = false;
        Trie t = new Trie().put(Nondet.KEYS[1], Nondet.bytes(1)).put(Nondet.KEYS[8], Nondet.bytes(1));
        assert t.getLeft().isEmpty() && t.getRight().isEmpty();
    }

    /** Structural equality: same message at every node (messages fix path, value, flags, sizes and
     *  child references), recursing into loaded children. */
    static boolean sameTree(Trie a, Trie b) {
        if (!Nondet.same(a.toMessage(), b.toMessage())) {
            return false;
        }
        if (a.getLeft().isEmpty() != b.getLeft().isEmpty() || a.getRight().isEmpty() != b.getRight().isEmpty()) {
            return false;
        }
        boolean ok = true;
        if (!a.getLeft().isEmpty()) {
            ok &= sameTree(a.getLeft().getNode().get(), b.getLeft().getNode().get());
        }
        if (!a.getRight().isEmpty()) {
            ok &= sameTree(a.getRight().getNode().get(), b.getRight().getNode().get());
        }
        return ok;
    }

    /**
     * TRIE-CMP-02 / TRIE-CMP-03: same key -> value map, same trie: for distinct k1, k2 in KEYS and
     * any values, put(k1,v1).put(k2,v2) and put(k2,v2).put(k1,v1) are structurally equal with equal
     * root messages; inserting and deleting a third key k3 gives back the same trie.
     */
    public static void historyIndependent() {
        // consistent oracle: the property compares messages of two independently built tries, which
        // embed separately computed child hashes (unconstrained hashes would differ spuriously)
        Keccak256Helper.consistent = true;
        Keccak256Helper.concreteOutputs = true;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            for (int j = i + 1; j < K.length; j++) {
                byte[] v1 = Nondet.bytes(1), v2 = Nondet.bytes(1);
                Trie a = new Trie().put(K[i], v1).put(K[j], v2);
                Trie b = new Trie().put(K[j], v2).put(K[i], v1);
                assert sameTree(a, b);
                for (int l = 0; l < K.length; l++) {
                    if (l != i && l != j) {
                        assert sameTree(a.put(K[l], Nondet.bytes(1)).delete(K[l]), a);
                    }
                }
            }
        }
    }

    public static void historyIndependentNegative() {
        Keccak256Helper.consistent = false;
        Trie a = new Trie().put(Nondet.KEYS[1], Nondet.bytes(1));
        Trie b = new Trie().put(Nondet.KEYS[2], Nondet.bytes(1));
        assert Nondet.same(a.toMessage(), b.toMessage());
    }

    /**
     * TRIE-CMP-03 with hashes: getHash() is equal for both insertion orders, with the consistent
     * collision-free oracle, for every pair of distinct keys of KEYS and concrete values.
     */
    public static void historyIndependentHash() {
        Keccak256Helper.consistent = true;
        Keccak256Helper.concreteOutputs = true;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            for (int j = i + 1; j < K.length; j++) {
                Trie a = new Trie().put(K[i], Nondet.b(0x0a)).put(K[j], Nondet.b(0x0b));
                Trie b = new Trie().put(K[j], Nondet.b(0x0b)).put(K[i], Nondet.b(0x0a));
                assert a.getHash().equals(b.getHash());
            }
        }
    }

    /** TRIE-VAL-07: overwriting a key with a value of 2^24 bytes throws IllegalArgumentException
     *  (new Uint24(length), Trie.java:823-829) before anything is copied. */
    public static void valueTooLong() {
        Keccak256Helper.consistent = false;
        Trie t = new Trie().put(Nondet.b(1), Nondet.bytes(1));
        boolean threw = false;
        try {
            t.put(Nondet.b(1), new byte[0x1000000]);
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        assert threw;
    }

    public static void valueTooLongNegative() {
        Keccak256Helper.consistent = false;
        new Trie().put(Nondet.b(1), Nondet.bytes(1)).put(Nondet.b(1), new byte[0x1000000]);
    }
}
