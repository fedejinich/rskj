import co.rsk.trie.Trie;
import co.rsk.trie.TrieStoreImpl;
import jbmcenv.MemoryKeyValueDataSource;
import org.ethereum.crypto.Keccak256Helper;

/**
 * Legacy (Orchid) format (Trie.toMessageOrchid / fromMessageOrchid, co/rsk/trie/Trie.java:177-257,
 * 525-583) on the real classes. Keccak: consistent oracle with concrete distinct outputs (child
 * Orchid hashes are copied into messages only). Tries from Nondet.KEYS, concrete values.
 */
public class OrchidHarness {
    static void layout(Trie n, boolean secure) {
        byte[] m = n.toMessageOrchid(secure);
        assert m[0] == 0x02;                                                   // SER-04 (Orchid side)
        int flags = m[1] & 0xFF;
        assert flags == ((secure ? 1 : 0) | (n.hasLongValue() ? 2 : 0));
        boolean hl = !n.getLeft().isEmpty(), hr = !n.getRight().isEmpty();
        int bits = ((m[2] & 0xFF) << 8) | (m[3] & 0xFF);
        assert bits == ((hl ? 1 : 0) | (hr ? 2 : 0));
        int l = n.getSharedPath().length();
        assert (((m[4] & 0xFF) << 8) | (m[5] & 0xFF)) == l;
        int pos = 6;
        if (l > 0) {
            assert Nondet.at(m, pos, n.getSharedPath().encode());
            pos += (l + 7) / 8;
        }
        if (hl) {
            assert Nondet.at(m, pos, n.getLeft().getNode().get().getHashOrchid(secure).getBytes());
            pos += 32;
        }
        if (hr) {
            assert Nondet.at(m, pos, n.getRight().getNode().get().getHashOrchid(secure).getBytes());
            pos += 32;
        }
        if (n.hasLongValue()) {
            assert Nondet.at(m, pos, n.getValueHash().getBytes());
            pos += 32;
        } else if (n.getValue() != null) {
            assert Nondet.at(m, pos, n.getValue());
            pos += n.getValue().length;
        }
        assert pos == m.length;
    }

    /** TRIE-SER-06 / TRIE-SER-04: toMessageOrchid(s) = 02 flags bitmask lshared path lhash rhash
     *  (valueHash | value), for tries of 1..2 keys of KEYS, both values of s, inline and long values. */
    public static void orchidLayout() {
        Keccak256Helper.concreteOutputs = true;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            for (int j = i + 1; j < K.length; j += 3) {
                for (boolean lv : new boolean[] {false, true}) {
                    Trie t = new Trie().put(K[i], lv ? Nondet.rep(33, 0x0c) : Nondet.b(0x0a)).put(K[j], Nondet.b(0x0b));
                    for (boolean s : new boolean[] {false, true}) {
                        layout(t, s);
                    }
                }
            }
        }
    }

    public static void orchidLayoutNegative() {
        Keccak256Helper.concreteOutputs = true;
        assert new Trie().put(Nondet.b(1), Nondet.b(0x0a)).toMessageOrchid(false)[0] == 0x40;
    }

    /**
     * TRIE-SER-07: fromMessage(toMessageOrchid(s)) (dispatched to fromMessageOrchid) has the node's
     * shared path and value and references the children by their Orchid hashes; with a long value
     * the value is retrieved from the store by valueHash.
     */
    public static void orchidParse() {
        Keccak256Helper.concreteOutputs = true;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            for (int j = i + 1; j < K.length; j += 3) {
                for (boolean lv : new boolean[] {false, true}) {
                    MemoryKeyValueDataSource db = new MemoryKeyValueDataSource();
                    TrieStoreImpl store = new TrieStoreImpl(db);
                    byte[] v = lv ? Nondet.rep(33, 0x0c) : Nondet.b(0x0a);
                    Trie t = new Trie(store).put(K[i], v).put(K[j], Nondet.b(0x0b));
                    if (lv) {
                        store.saveValue(v);
                    }
                    for (boolean s : new boolean[] {false, true}) {
                        Trie u = Trie.fromMessage(t.toMessageOrchid(s), store);
                        assert u.getSharedPath().length() == t.getSharedPath().length();
                        for (int x = 0; x < t.getSharedPath().length(); x++) {
                            assert u.getSharedPath().get(x) == t.getSharedPath().get(x);
                        }
                        assert Nondet.same(u.getValue(), t.getValue());
                        if (!t.getLeft().isEmpty()) {
                            assert u.getLeft().getHash().get().equals(t.getLeft().getNode().get().getHashOrchid(s));
                        }
                        if (!t.getRight().isEmpty()) {
                            assert u.getRight().getHash().get().equals(t.getRight().getNode().get().getHashOrchid(s));
                        }
                    }
                }
            }
        }
    }

    public static void orchidParseNegative() {
        Keccak256Helper.concreteOutputs = true;
        Trie t = new Trie().put(Nondet.b(1), Nondet.b(0x0a));
        assert Trie.fromMessage(t.toMessageOrchid(false), null).getValue() == null;
    }
}
