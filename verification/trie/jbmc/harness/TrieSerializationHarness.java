import co.rsk.trie.NodeReference;
import co.rsk.trie.Trie;
import org.ethereum.crypto.Keccak256Helper;

/**
 * Trie.toMessage -> Trie.fromMessage (co/rsk/trie/Trie.java:163-347, 506-739) round trip on the real
 * class, for the root and both children of every trie with 1..3 distinct keys of the concrete
 * universe Nondet.KEYS (why concrete: TrieOpsHarness), and one-key tries with values of 1, 32, 33 bytes. Covers shared paths, embedded children,
 * hash-referenced (non-terminal) children and long (33-byte, stored by hash) values.
 * Keccak is unconstrained: the round trip does not depend on digest values.
 */
public class TrieSerializationHarness {
    /** fromMessage(toMessage(n)) re-serializes to the same bytes and keeps the node's fields. */
    static void checkNode(Trie t) {
        byte[] m = t.toMessage();
        Trie u = Trie.fromMessage(m, null);
        assert Nondet.same(u.toMessage(), m);
        assert u.getSharedPath().length() == t.getSharedPath().length();
        for (int i = 0; i < t.getSharedPath().length(); i++) {
            assert u.getSharedPath().get(i) == t.getSharedPath().get(i);
        }
        assert u.getValueLength().equals(t.getValueLength());
        assert u.hasLongValue() == t.hasLongValue();
        if (t.hasLongValue()) {
            assert u.getValueHash().equals(t.getValueHash());
        } else {
            assert Nondet.same(u.getValue(), t.getValue());
        }
        assert u.getLeft().isEmpty() == t.getLeft().isEmpty();
        assert u.getRight().isEmpty() == t.getRight().isEmpty();
        assert u.getLeft().isEmbeddable() == t.getLeft().isEmbeddable();
        assert u.getRight().isEmbeddable() == t.getRight().isEmbeddable();
    }

    static void checkTree(Trie t) {
        checkNode(t);
        NodeReference[] children = {t.getLeft(), t.getRight()};
        for (NodeReference r : children) {
            if (!r.isEmpty()) {
                checkNode(r.getNode().get());
            }
        }
    }

    /** Every trie with 1..3 keys from Nondet.KEYS and symbolic values, root and children. */
    public static void roundTrip() {
        Keccak256Helper.consistent = false;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            for (int vl : TrieOpsHarness.FIRST_VALUE_LENGTHS) {
                Trie t1 = new Trie().put(K[i], Nondet.bytes(vl));
                checkTree(t1);
                // SplitHarness: LO2/HI2 select the second key (default: every key after K[i])
                for (int j = Math.max(i + 1, Nondet.LO2); j < Math.min(Nondet.HI2, K.length); j++) {
                    Trie t2 = t1.put(K[j], Nondet.bytes(1));
                    checkTree(t2);
                    for (int l = j + 1; l < K.length; l++) {
                        checkTree(t2.put(K[l], Nondet.bytes(1)));
                    }
                }
            }
        }
    }

    /** One-key tries: every key in KEYS with every value length in VALUE_LENGTHS (1, 32, 33). */
    public static void singleKeyRoundTrip() {
        Keccak256Helper.consistent = false;
        for (byte[] k : Nondet.KEYS) {
            for (int vl : Nondet.VALUE_LENGTHS) {
                checkTree(new Trie().put(k, Nondet.bytes(vl)));
            }
        }
    }

    /** Negative control: claims no serialized root ever has an embedded child. */
    public static void roundTripNegative() {
        Keccak256Helper.consistent = false;
        byte[][] K = Nondet.KEYS;
        for (int j = 2; j < K.length; j++) {
            Trie t = new Trie().put(K[1], Nondet.bytes(1)).put(K[j], Nondet.bytes(1));
            Trie u = Trie.fromMessage(t.toMessage(), null);
            assert !u.getLeft().isEmbeddable() && !u.getRight().isEmbeddable();
        }
    }

    /** Negative control: claims no node ever references a child by hash (non-terminal child). */
    public static void hashChildNegative() {
        Keccak256Helper.consistent = false;
        Trie t = new Trie().put(Nondet.KEYS[0], Nondet.bytes(1)).put(Nondet.KEYS[1], Nondet.bytes(1))
                .put(Nondet.KEYS[8], Nondet.bytes(1)).put(Nondet.KEYS[5], Nondet.bytes(1));
        Trie u = Trie.fromMessage(t.toMessage(), null);
        assert (u.getLeft().isEmpty() || u.getLeft().isEmbeddable())
                && (u.getRight().isEmpty() || u.getRight().isEmbeddable());
    }

    /** Negative control for singleKeyRoundTrip: claims the value length never survives. */
    public static void singleKeyRoundTripNegative() {
        Keccak256Helper.consistent = false;
        Trie t = new Trie().put(Nondet.KEYS[9], Nondet.bytes(Nondet.LONG_VALUE));
        assert Trie.fromMessage(t.toMessage(), null).getValueLength().intValue() == 0;
    }
}
