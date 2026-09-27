import co.rsk.trie.Trie;
import co.rsk.trie.TrieDTO;
import co.rsk.trie.TrieStoreImpl;
import jbmcenv.MemoryKeyValueDataSource;
import org.ethereum.crypto.Keccak256Helper;

/**
 * TrieDTO (co/rsk/trie/TrieDTO.java, snapshot-sync node representation) against Trie on the node
 * format, on the real classes. Keccak: consistent oracle with concrete distinct outputs.
 */
public class DtoHarness {
    /** TRIE-SER-08 (Java, where it agrees): for tries of 1..2 keys of KEYS with inline values,
     *  TrieDTO.decodeFromMessage(m, store).toMessage() == m for the root message m. */
    public static void dtoRoundTripInline() {
        Keccak256Helper.concreteOutputs = true;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            for (int j = i; j < K.length; j += 3) {
                TrieStoreImpl s = new TrieStoreImpl(new MemoryKeyValueDataSource());
                Trie t = new Trie(s).put(K[i], Nondet.b(0x0a)).put(K[j], Nondet.b(0x0b));
                s.save(t);
                byte[] m = t.toMessage();
                assert Nondet.same(TrieDTO.decodeFromMessage(m, s).toMessage(), m);
            }
        }
    }

    public static void dtoRoundTripInlineNegative() {
        Keccak256Helper.concreteOutputs = true;
        TrieStoreImpl s = new TrieStoreImpl(new MemoryKeyValueDataSource());
        Trie t = new Trie(s).put(Nondet.KEYS[1], Nondet.b(0x0a));
        s.save(t);
        assert TrieDTO.decodeFromMessage(t.toMessage(), s).toMessage().length == 1;
    }

    static final byte[] V33 = Nondet.rep(33, 0xab);

    /** m08 (Lean Ser.lean): root 5f 06 00 24 [60 H 000021] 02 [40 02] 47 with an embedded long-value
     *  left child, H = keccak(33xab) (oracle), and a store mapping H -> 33xab. */
    static byte[] m08() {
        byte[] h = Keccak256Helper.keccak256(V33);
        return Nondet.cat(Nondet.b(0x5f, 0x06, 0x00, 0x24, 0x60), h, Nondet.b(0x00, 0x00, 0x21, 0x02, 0x40, 0x02, 0x47));
    }

    static TrieStoreImpl store08() {
        MemoryKeyValueDataSource db = new MemoryKeyValueDataSource();
        db.put(Keccak256Helper.keccak256(V33), V33);
        return new TrieStoreImpl(db);
    }

    /** TRIE-SER-08 (Java, reproducer): m08 is canonical for Trie (fromMessage(m08).toMessage() ==
     *  m08) but TrieDTO re-emits the embedded long-value child in its sync form, value inline:
     *  5f 06 00 22 60 33xab 02 40 02 47. */
    public static void dtoEmbeddedLongValue() {
        Keccak256Helper.concreteOutputs = true;
        byte[] m = m08();
        TrieStoreImpl s = store08();
        assert Nondet.same(Trie.fromMessage(m, s).toMessage(), m);
        byte[] expected = Nondet.cat(Nondet.b(0x5f, 0x06, 0x00, 0x22, 0x60), V33, Nondet.b(0x02, 0x40, 0x02, 0x47));
        assert Nondet.same(TrieDTO.decodeFromMessage(m, s).toMessage(), expected);
    }

    /** TRIE-SER-08 rskip-reading: TrieDTO.decodeFromMessage(m).toMessage() == m for canonical m. */
    public static void dtoEmbeddedLongValueRskip() {
        Keccak256Helper.concreteOutputs = true;
        byte[] m = m08();
        assert Nondet.same(TrieDTO.decodeFromMessage(m, store08()).toMessage(), m);
    }
}
