import co.rsk.bitcoinj.core.VarInt;
import co.rsk.trie.NodeReference;
import co.rsk.trie.Trie;
import org.ethereum.crypto.Keccak256Helper;

/**
 * RSKIP107 node format (Trie.toMessage, co/rsk/trie/Trie.java:677-739; NodeReference.java:141-195) on
 * the real classes. checkNode re-derives every field of a node's message from the node's own
 * accessors, independently of the serializer (bits packed by hand, lshared prefix from the RSKIP
 * table, VarInt from the separately verified co.rsk.bitcoinj.core.VarInt), and is applied to every
 * node of tries built by put/delete from the concrete key universe Nondet.KEYS with values of
 * nondet content (lengths 1, 32, 33). Keccak is unconstrained: digests are only copied, and child
 * hashes are compared with the NodeReference's own cached hash.
 */
public class NodeHarness {
    static int ref(byte[] m, int pos, NodeReference r) {
        if (r.isEmpty()) {
            return pos;
        }
        if (r.isEmbeddable()) { // TRIE-NODE-06, TRIE-EMB-05: uint8 length ++ child message
            byte[] cm = r.getNode().get().toMessage();
            assert (m[pos] & 0xFF) == cm.length;
            assert Nondet.at(m, pos + 1, cm);
            return pos + 1 + cm.length;
        }
        byte[] h = r.getHash().get().getBytes(); // TRIE-NODE-06: 32-byte hash
        assert h.length == 32 && Nondet.at(m, pos, h);
        return pos + 32;
    }

    static int lsharedPrefix(byte[] m, int pos, int l) { // TRIE-LSH-01..03 inside a message
        int b0 = m[pos] & 0xFF;
        if (l <= 32) {
            assert b0 == l - 1;
            return pos + 1;
        }
        if (l >= 160 && l <= 382) {
            assert b0 == l - 128;
            return pos + 1;
        }
        assert b0 == 255;
        byte[] v = new VarInt(l).encode();
        assert Nondet.at(m, pos + 1, v);
        return pos + 1 + v.length;
    }

    /** Checks the format obligations on node n (see the entry list in harnesses.json). */
    static void checkNode(Trie n) {
        byte[] m = n.toMessage();
        int f = m[0] & 0xFF;
        assert (f & 0xC0) == 0x40;                                          // NODE-01
        assert f >= 0x40 && f <= 0x7F;                                       // SER-04 (RSKIP107 side)
        assert ((f & 0x20) != 0) == n.hasLongValue();                        // NODE-03
        assert n.hasLongValue() == (n.getValueLength().intValue() > 32);     // VAL-01
        int l = n.getSharedPath().length();
        assert ((f & 0x10) != 0) == (l > 0);                                 // LSH-04
        NodeReference left = n.getLeft(), right = n.getRight();
        assert ((f & 0x08) != 0) == !left.isEmpty();                         // NODE-04 (Java bits)
        assert ((f & 0x04) != 0) == !right.isEmpty();
        assert ((f & 0x02) != 0) == left.isEmbeddable();
        assert ((f & 0x01) != 0) == right.isEmbeddable();
        int pos = 1;                                                         // NODE-05 field order
        if (l > 0) {
            pos = lsharedPrefix(m, pos, l);
            int enc = (l + 7) / 8;
            for (int i = 0; i < 8 * enc; i++) {                              // PATH-03 inside messages
                int bit = (m[pos + i / 8] >> (7 - i % 8)) & 1;
                assert bit == (i < l ? n.getSharedPath().get(i) : 0);
            }
            pos += enc;
        }
        pos = ref(m, pos, left);
        pos = ref(m, pos, right);
        if (!n.isTerminal()) {                                               // NODE-07 (Java condition)
            byte[] cs = new VarInt(n.getChildrenSize().value).encode();
            assert Nondet.at(m, pos, cs);
            pos += cs.length;
        }
        if (n.hasLongValue()) {                                              // NODE-08 (Java order), VAL-02
            assert Nondet.at(m, pos, n.getValueHash().getBytes());
            pos += 32;
            int vl = n.getValueLength().intValue();                          // VAL-04 big-endian uint24
            assert Nondet.at(m, pos, Nondet.b(vl >> 16, vl >> 8, vl));
            pos += 3;
        } else {                                                             // NODE-09
            byte[] v = n.getValue();
            if (v != null) {
                assert Nondet.at(m, pos, v);
                pos += v.length;
            }
        }
        assert pos == m.length;
        long size = 0;
        NodeReference[] refs = {left, right};
        for (NodeReference r : refs) {
            if (!r.isEmpty()) {
                Trie c = r.getNode().get();
                if (r.isEmbeddable()) {
                    assert c.isTerminal();                                   // EMB-01
                }
                assert r.isEmbeddable() == (c.isTerminal() && c.getMessageLength() <= 44); // EMB-04
                size += c.getMessageLength() + c.getChildrenSize().value
                        + (c.hasLongValue() ? c.getValueLength().intValue() : 0);
            }
        }
        assert n.getChildrenSize().value == size;                            // SIZE-01
        Trie copy = new Trie(null, n.getSharedPath(), n.getValue(), left, right, n.getValueLength(),
                n.getValueHash());                                           // childrenSize == null
        assert copy.getChildrenSize().value == n.getChildrenSize().value;    // SIZE-02
    }

    static void checkTree(Trie t) {
        checkNode(t);
        NodeReference[] refs = {t.getLeft(), t.getRight()};
        for (NodeReference r : refs) {
            if (!r.isEmpty()) {
                checkTree(r.getNode().get());
            }
        }
    }

    /** One-key tries: every key of KEYS, every value length 1/32/33, and the empty trie. */
    public static void format1() {
        Keccak256Helper.consistent = false;
        checkTree(new Trie());
        for (byte[] k : Nondet.KEYS) {
            for (int vl : Nondet.VALUE_LENGTHS) {
                checkTree(new Trie().put(k, Nondet.bytes(vl)));
            }
        }
    }

    /** Two-key tries: every pair of distinct keys of KEYS; first value 1 or 33 bytes. */
    public static void format2() {
        Keccak256Helper.consistent = false;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            for (int vl : TrieOpsHarness.FIRST_VALUE_LENGTHS) {
                Trie t1 = new Trie().put(K[i], Nondet.bytes(vl));
                for (int j = 0; j < K.length; j++) {
                    if (!Nondet.in2(j)) continue; // SplitHarness: one second key per part
                    if (j != i) {
                        checkTree(t1.put(K[j], Nondet.bytes(1)));
                    }
                }
            }
        }
    }

    /** Three-key tries (every triple of KEYS) and the tries left after deleting each of the keys. */
    public static void format3() {
        Keccak256Helper.consistent = false;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            for (int j = i + 1; j < K.length; j++) {
                Trie t2 = new Trie().put(K[i], Nondet.bytes(1)).put(K[j], Nondet.bytes(1));
                if (!Nondet.in2(j)) continue; // SplitHarness: one second key per part
                for (int l = j + 1; l < K.length; l++) {
                    Trie t3 = t2.put(K[l], Nondet.bytes(1));
                    checkTree(t3);
                    checkTree(t3.delete(K[i]));
                    checkTree(t3.delete(K[j]));
                }
            }
        }
    }

    /** Negative control shared by the format harnesses: claims no node has the prefix flag. */
    public static void formatNegative() {
        Keccak256Helper.consistent = false;
        for (byte[] k : Nondet.KEYS) {
            assert (new Trie().put(k, Nondet.bytes(1)).toMessage()[0] & 0x10) == 0;
        }
    }

    /**
     * TRIE-SER-02: on canonical nodes the encoding is injective: for every pair of one- or two-key
     * tries over KEYS, equal root messages imply equal shared path, value, childrenSize and child
     * references (equal embedded child messages or equal hashes).
     */
    public static void encodingInjective() {
        Keccak256Helper.consistent = false;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            Trie a = new Trie().put(K[i], Nondet.bytes(1)).put(K[(i + 1) % K.length], Nondet.bytes(1));
            for (int j = 0; j < K.length; j++) {
                Trie b = new Trie().put(K[j], Nondet.bytes(1));
                if (!Nondet.in2(j)) continue; // SplitHarness: one second key per part
                Trie[] cands = {b, b.put(K[(j + 1) % K.length], Nondet.bytes(1))};
                for (Trie c : cands) {
                    if (Nondet.same(a.toMessage(), c.toMessage())) {
                        assert a.getSharedPath().length() == c.getSharedPath().length();
                        for (int x = 0; x < a.getSharedPath().length(); x++) {
                            assert a.getSharedPath().get(x) == c.getSharedPath().get(x);
                        }
                        assert Nondet.same(a.getValue(), c.getValue());
                        assert a.getChildrenSize().value == c.getChildrenSize().value;
                        assert sameRef(a.getLeft(), c.getLeft()) && sameRef(a.getRight(), c.getRight());
                    }
                }
            }
        }
    }

    static boolean sameRef(NodeReference x, NodeReference y) {
        if (x.isEmpty() || y.isEmpty()) {
            return x.isEmpty() == y.isEmpty();
        }
        if (x.isEmbeddable() != y.isEmbeddable()) {
            return false;
        }
        if (x.isEmbeddable()) {
            return Nondet.same(x.getNode().get().toMessage(), y.getNode().get().toMessage());
        }
        return Nondet.same(x.getHash().get().getBytes(), y.getHash().get().getBytes());
    }

    public static void encodingInjectiveNegative() {
        Keccak256Helper.consistent = false;
        Trie a = new Trie().put(Nondet.KEYS[1], Nondet.bytes(1));
        Trie b = new Trie().put(Nondet.KEYS[1], Nondet.bytes(1));
        assert !Nondet.same(a.toMessage(), b.toMessage());
    }

    // ---- exact-byte reproducers (differential/cases/reproducers.cases, Lean Examples.lean) ----

    static final byte[] V32 = Nondet.rep(32, 0x5a);
    static final byte[] V33 = Nondet.rep(33, 0xab);

    static Trie exA() { // {00: 01, 0000: 02}
        return new Trie().put(Nondet.b(0x00), Nondet.b(0x01)).put(Nondet.b(0x00, 0x00), Nondet.b(0x02));
    }

    static Trie exB() { // {00x8: 32x5a, 80 00x7: 32x5a}
        return new Trie().put(Nondet.rep(8, 0), V32).put(Nondet.cat(Nondet.b(0x80), Nondet.rep(7, 0)), V32);
    }

    static Trie exC() { // {01: 33xab, 0101: 02}
        return new Trie().put(Nondet.b(0x01), V33).put(Nondet.b(0x01, 0x01), Nondet.b(0x02));
    }

    static byte[] leafB() {
        return Nondet.cat(Nondet.b(0x50, 0xff, 0x3f), Nondet.rep(8, 0), V32);
    }

    /** TRIE-NODE-04 (Java): exA's root is 5a070004500600020401: left present 0x08 + left embedded 0x02. */
    public static void flagsExA() {
        Keccak256Helper.consistent = false;
        assert Nondet.same(exA().toMessage(), Nondet.b(0x5a, 0x07, 0x00, 0x04, 0x50, 0x06, 0x00, 0x02, 0x04, 0x01));
    }

    /** TRIE-NODE-04 rskip-reading: both RSKIP readings of the child bits give flags 0x55 here. */
    public static void flagsExARskip() {
        Keccak256Helper.consistent = false;
        assert exA().toMessage()[0] == 0x55;
    }

    /** TRIE-NODE-07 / TRIE-EMB-03 (Java): exB's root is 4f 2b leaf 2b leaf 56 with 43-byte leaves
     *  50 ff 3f 00x8 32x5a that carry no treeSize; the root carries childrenSize 0x56 = 86. */
    public static void treeSizeExB() {
        Keccak256Helper.consistent = false;
        byte[] leaf = leafB();
        assert leaf.length == 43;
        assert Nondet.same(exB().toMessage(), Nondet.cat(Nondet.b(0x4f, 0x2b), leaf, Nondet.b(0x2b), leaf, Nondet.b(0x56)));
    }

    /** TRIE-NODE-07 rskip-reading: treeSize is written iff the node has no children, so a leaf's
     *  message would be one byte longer than its fields (43 + 1). */
    public static void treeSizeExBRskip() {
        Keccak256Helper.consistent = false;
        Trie t = exB();
        assert t.getLeft().getNode().get().toMessage().length == 44;
    }

    /** TRIE-EMB-03 rskip-reading: an embedded child encoding is at most 40 bytes. */
    public static void embedLimitExBRskip() {
        Keccak256Helper.consistent = false;
        assert (exB().toMessage()[1] & 0xFF) <= 40;
    }

    /** TRIE-NODE-08 (Java): exC's root is 7a 07 01 04 50060202 04 keccak(33xab) 000021. */
    public static void longValueOrderExC() {
        byte[] m = exC().toMessage();
        assert Nondet.same(m, Nondet.cat(Nondet.b(0x7a, 0x07, 0x01, 0x04, 0x50, 0x06, 0x02, 0x02, 0x04),
                Keccak256Helper.keccak256(V33), Nondet.b(0x00, 0x00, 0x21)));
    }

    /** TRIE-NODE-08 rskip-reading: literal order ... right reference, valueHash, valueLength, treeSize. */
    public static void longValueOrderExCRskip() {
        byte[] m = exC().toMessage();
        assert Nondet.at(m, 8, Keccak256Helper.keccak256(V33));
    }
}
