import co.rsk.trie.Trie;
import org.ethereum.crypto.Keccak256Helper;
import org.ethereum.util.RLP;

/**
 * Node and root hashes (Trie.getHash / getValueHash / getHashOrchid, co/rsk/trie/Trie.java:362-395,
 * 975-983) on the real classes, against the consistent collision-free Keccak oracle (Keccak256Helper
 * model): the harness asks the oracle for keccak(x) of the expected input x and compares.
 * Concrete digests (concreteOutputs) are used where noted; see the model header for why that result
 * carries over to every collision-free assignment (digests are only compared and copied).
 */
public class HashHarness {
    static byte[] k(byte[] x) {
        return Keccak256Helper.keccak256(x);
    }

    /** TRIE-HASH-01: getHash() == keccak(toMessage()) for every non-empty trie of 1..2 keys of
     *  KEYS with concrete values, and for one-key tries with a symbolic 1-byte value. */
    public static void nodeHash() {
        Keccak256Helper.concreteOutputs = true;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            Trie t1 = new Trie().put(K[i], Nondet.b(0x0a));
            assert Nondet.same(t1.getHash().getBytes(), k(t1.toMessage()));
            for (int j = i + 1; j < K.length; j++) {
                if (!Nondet.in2(j)) continue; // SplitHarness: one second key per part (oracle table size)
                Trie t2 = t1.put(K[j], Nondet.rep(33, 0x0b));
                assert Nondet.same(t2.getHash().getBytes(), k(t2.toMessage()));
            }
        }
    }

    public static void nodeHashSymbolicValue() {
        byte[] v = Nondet.bytes(1);
        Trie t = new Trie().put(Nondet.b(0x01), v);
        assert Nondet.same(t.getHash().getBytes(), k(t.toMessage()));
    }

    public static void nodeHashNegative() {
        Trie t = new Trie().put(Nondet.b(0x01), Nondet.bytes(1));
        Trie u = new Trie().put(Nondet.b(0x02), Nondet.bytes(1));
        assert Nondet.same(t.getHash().getBytes(), k(u.toMessage()));
    }

    /** TRIE-HASH-02 (Java): the empty trie hashes to keccak(RLP.encodeElement([])) = keccak(80),
     *  its message is 40, and that hash differs from keccak(40). */
    public static void emptyHash() {
        Trie e = new Trie();
        assert Nondet.same(RLP.encodeElement(new byte[0]), Nondet.b(0x80));
        assert Nondet.same(e.getHash().getBytes(), k(Nondet.b(0x80)));
        assert Nondet.same(e.toMessage(), Nondet.b(0x40));
        assert !Nondet.same(e.getHash().getBytes(), k(Nondet.b(0x40)));
    }

    /** TRIE-HASH-02 rskip-reading: the root hash is keccak(toMessage()) for the empty trie too. */
    public static void emptyHashRskip() {
        Trie e = new Trie();
        assert Nondet.same(e.getHash().getBytes(), k(e.toMessage()));
    }

    /** TRIE-HASH-03: with an injective hash, equal root hashes imply equal maps: for one-key tries
     *  over KEYS with symbolic 1-byte values, getHash equal implies same key and same value. */
    public static void hashBindsMap() {
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            byte[] v1 = Nondet.bytes(1);
            Trie t1 = new Trie().put(K[i], v1);
            for (int j = i; j < K.length; j++) {
                byte[] v2 = Nondet.bytes(1);
                if (!Nondet.in2(j)) continue; // SplitHarness: one second key per part
                Trie t2 = new Trie().put(K[j], v2);
                if (t1.getHash().equals(t2.getHash())) {
                    assert i == j && Nondet.same(v1, v2);
                }
            }
        }
    }

    public static void hashBindsMapNegative() {
        Trie t1 = new Trie().put(Nondet.KEYS[1], Nondet.bytes(1));
        Trie t2 = new Trie().put(Nondet.KEYS[1], Nondet.bytes(1));
        assert !t1.getHash().equals(t2.getHash());
    }

    /** TRIE-VAL-03: getValueHash() == keccak(getValue()) for values of 1, 32 and 33 symbolic bytes. */
    public static void valueHash() {
        for (int vl : Nondet.VALUE_LENGTHS) {
            byte[] v = Nondet.bytes(vl);
            Trie t = new Trie().put(Nondet.b(0x01), v);
            assert Nondet.same(t.getValueHash().getBytes(), k(v));
        }
    }

    public static void valueHashNegative() {
        byte[] v = Nondet.bytes(1);
        Trie t = new Trie().put(Nondet.b(0x01), v);
        assert Nondet.same(t.getValueHash().getBytes(), k(t.toMessage()));
    }

    /** TRIE-HASH-05: getHashOrchid(s) == keccak(toMessageOrchid(s)) for non-empty tries of 2 keys
     *  of KEYS, each s on a fresh trie, and the empty trie's Orchid hash is getHash()'s EMPTY_HASH.
     *  Narrowed to one s per trie instance: the Orchid hash cache ignores s (orchidCacheIgnoresSecure). */
    public static void orchidHash() {
        Keccak256Helper.concreteOutputs = true;
        assert new Trie().getHashOrchid(false).equals(new Trie().getHash());
        assert new Trie().getHashOrchid(true).equals(new Trie().getHash());
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            for (int j = i + 1; j < K.length; j += 3) {
                for (boolean s : new boolean[] {false, true}) {
                    Trie t = new Trie().put(K[i], Nondet.b(0x0a)).put(K[j], Nondet.b(0x0b));
                    assert Nondet.same(t.getHashOrchid(s).getBytes(), k(t.toMessageOrchid(s)));
                }
            }
        }
    }

    /** TRIE-HASH-05 as stated, for both s on one trie: after getHashOrchid(false), getHashOrchid(true)
     *  returns the cached false hash (Trie.java:382-383), not keccak(toMessageOrchid(true)). */
    public static void orchidCacheIgnoresSecure() {
        Keccak256Helper.concreteOutputs = true;
        Trie t = new Trie().put(Nondet.b(1), Nondet.b(0x0a));
        t.getHashOrchid(false);
        assert Nondet.same(t.getHashOrchid(true).getBytes(), k(t.toMessageOrchid(true)));
    }

    public static void orchidHashNegative() {
        Keccak256Helper.concreteOutputs = true;
        Trie t = new Trie().put(Nondet.b(1), Nondet.b(0x0a));
        assert t.getHashOrchid(false).equals(t.getHash());
    }
}
