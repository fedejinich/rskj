import co.rsk.trie.Trie;
import org.ethereum.crypto.Keccak256Helper;

/**
 * Trie put/get/delete (co/rsk/trie/Trie.java:405-472, 770-940) on the real class against finite-map
 * semantics.
 *
 * Values have nondet contents and concrete lengths: single-key harnesses use every length in
 * Nondet.VALUE_LENGTHS (1, 32, 33); multi-key harnesses give the first key a 1- or 33-byte value
 * (inline or long) and later keys 1-byte values. Keys: singleKeyPutGet uses fully symbolic keys of
 * 0..2 bytes; the other harnesses range over every key/pair/triple of the concrete universe
 * Nondet.KEYS.
 * Reason: with two symbolic keys JBMC 6.11 cannot simplify the per-bit decode branches of equal key
 * bits, the shared-path lengths become symbolic and symbolic execution did not finish in 30 minutes
 * even for two one-byte keys (see README.md). Keccak runs unconstrained (Keccak256Helper header):
 * these properties do not depend on digest values, and SUCCESS then holds for any hash function.
 */
public class TrieOpsHarness {
    /** Lengths of the first inserted value in multi-key harnesses: inline and long. */
    static final int[] FIRST_VALUE_LENGTHS = {1, Nondet.LONG_VALUE};

    static byte[] lookup(byte[] q, byte[][] ks, byte[][] vs, int n) {
        byte[] r = null;
        for (int i = 0; i < n; i++) {
            if (Nondet.same(q, ks[i])) {
                r = vs[i]; // later puts win
            }
        }
        return r;
    }

    /** Fully symbolic keys: after put(k,v), get(q) is v iff q == k, for all k, q of 0..2 bytes. */
    public static void singleKeyPutGet() {
        Keccak256Helper.consistent = false;
        for (int lk = 0; lk <= 2; lk++) {
          for (int vl : Nondet.VALUE_LENGTHS) {
            byte[] k = Nondet.bytes(lk);
            byte[] v = Nondet.bytes(vl);
            Trie t = new Trie().put(k, v);
            assert Nondet.same(t.get(k), v);
            for (int lq = 0; lq <= 2; lq++) {
                byte[] q = Nondet.bytes(lq);
                assert Nondet.same(t.get(q), Nondet.same(q, k) ? v : null);
            }
          }
        }
    }

    /**
     * put(k,v) then delete(k) or put(k, empty) gives the canonical empty trie, for every k in KEYS
     * and every value length in VALUE_LENGTHS. (Keys concrete: deleting a symbolic key compares two
     * decodings of the same symbolic bytes, which JBMC 6.11 cannot simplify; see README.md.)
     */
    public static void singleKeyDelete(boolean viaEmptyValue) {
        Keccak256Helper.consistent = false;
        for (byte[] k : Nondet.KEYS) {
            for (int vl : Nondet.VALUE_LENGTHS) {
                Trie t = new Trie().put(k, Nondet.bytes(vl));
                Trie d = viaEmptyValue ? t.put(k, new byte[0]) : t.delete(k);
                assert d.isEmptyTrie();
                assert d.get(k) == null;
                assert d.getSharedPath().length() == 0;
            }
        }
    }

    /** After put(k1,v1).put(k2,v2), for every k1, k2 in KEYS: get(q) follows the map for all q in KEYS. */
    public static void putGet() {
        Keccak256Helper.consistent = false;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
          for (int vl : FIRST_VALUE_LENGTHS) {
            byte[] v1 = Nondet.bytes(vl);
            Trie t1 = new Trie().put(K[i], v1);
            for (int j = 0; j < K.length; j++) {
                byte[] v2 = Nondet.bytes(1);
                Trie t = t1.put(K[j], v2);
                byte[][] ks = {K[i], K[j]};
                byte[][] vs = {v1, v2};
                for (byte[] q : K) {
                    assert Nondet.same(t.get(q), lookup(q, ks, vs, 2));
                }
            }
          }
        }
    }

    /**
     * Delete via delete(k) or put(k, empty): after put(k1,v1).put(k2,v2).del(kd), for every k1, k2, kd
     * in KEYS, get(q) follows the map with kd removed for all q in KEYS, the original trie is
     * unchanged, and deleting every key gives the empty trie.
     */
    public static void putDeleteGet(boolean viaEmptyValue) {
        Keccak256Helper.consistent = false;
        // SplitHarness: LO3/HI3 fix the deletion mode (0 = delete(k), 1 = put(k, empty)), LO2/HI2 the deleted key
        if (Nondet.HI3 == Nondet.LO3 + 1) viaEmptyValue = Nondet.LO3 == 1;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
          for (int vl : FIRST_VALUE_LENGTHS) {
            byte[] v1 = Nondet.bytes(vl);
            Trie t1 = new Trie().put(K[i], v1);
            for (int j = 0; j < K.length; j++) {
                byte[] v2 = Nondet.bytes(1);
                Trie t = t1.put(K[j], v2);
                byte[][] ks = {K[i], K[j]};
                byte[][] vs = {v1, v2};
                for (int l = Nondet.LO2; l < Math.min(Nondet.HI2, K.length); l++) {
                    byte[] kd = K[l];
                    Trie d = viaEmptyValue ? t.put(kd, new byte[0]) : t.delete(kd);
                    for (byte[] q : K) {
                        byte[] before = lookup(q, ks, vs, 2);
                        assert Nondet.same(t.get(q), before);
                        assert Nondet.same(d.get(q), Nondet.same(q, kd) ? null : before);
                    }
                    assert d.isEmptyTrie() == (Nondet.same(kd, K[i]) && Nondet.same(kd, K[j]));
                }
            }
          }
        }
    }

    /** put(k, empty) and delete(k) give identical serializations, from every 2-key trie over KEYS. */
    public static void emptyValueIsDelete() {
        // consistent oracle: the property compares messages of two independently built tries, which
        // embed separately computed child hashes (unconstrained hashes would differ spuriously)
        Keccak256Helper.consistent = true;
        Keccak256Helper.concreteOutputs = true;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
          for (int vl : FIRST_VALUE_LENGTHS) {
            Trie t1 = new Trie().put(K[i], Nondet.bytes(vl));
            // SplitHarness: LO2/HI2 select the second key
            for (int j = Nondet.LO2; j < Math.min(Nondet.HI2, K.length); j++) {
                Trie t = t1.put(K[j], Nondet.bytes(1));
                for (byte[] kd : K) {
                    assert Nondet.same(t.put(kd, new byte[0]).toMessage(), t.delete(kd).toMessage());
                }
            }
          }
        }
    }

    /** Negative control for singleKeyPutGet: claims get(q) is null for every probe q (false for q == k). */
    public static void singleKeyPutGetNegative() {
        Keccak256Helper.consistent = false;
        byte[] k = Nondet.bytes(1);
        Trie t = new Trie().put(k, Nondet.bytes(Nondet.LONG_VALUE));
        assert t.get(Nondet.bytes(1)) == null;
    }

    /** Negative control for singleKeyDelete: claims the trie is still non-empty after deleting k. */
    public static void singleKeyDeleteNegative(boolean viaEmptyValue) {
        Keccak256Helper.consistent = false;
        byte[] k = Nondet.KEYS[9];
        Trie t = new Trie().put(k, Nondet.bytes(Nondet.LONG_VALUE));
        Trie d = viaEmptyValue ? t.put(k, new byte[0]) : t.delete(k);
        assert !d.isEmptyTrie();
    }

    /** Negative control for putGet: claims get(k1) is always v1 (false when k2 == k1). */
    public static void putGetNegative() {
        Keccak256Helper.consistent = false;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
          for (int vl : FIRST_VALUE_LENGTHS) {
            byte[] v1 = Nondet.bytes(vl);
            for (int j = 0; j < K.length; j++) {
                Trie t = new Trie().put(K[i], v1).put(K[j], Nondet.bytes(1));
                assert Nondet.same(t.get(K[i]), v1);
            }
          }
        }
    }

    /** Negative control for putDeleteGet: claims deleting kd never affects get(k2). */
    public static void putDeleteGetNegative(boolean viaEmptyValue) {
        Keccak256Helper.consistent = false;
        byte[][] K = Nondet.KEYS;
        for (int j = 0; j < K.length; j++) {
            byte[] v2 = Nondet.bytes(1);
            Trie t = new Trie().put(K[1], Nondet.bytes(Nondet.LONG_VALUE)).put(K[j], v2);
            Trie d = viaEmptyValue ? t.put(K[j], new byte[0]) : t.delete(K[j]);
            assert Nondet.same(d.get(K[j]), v2);
        }
    }

    /** Negative control for emptyValueIsDelete: claims put(k, empty) never changes the trie. */
    public static void emptyValueIsDeleteNegative() {
        Keccak256Helper.consistent = false;
        Trie t = new Trie().put(Nondet.KEYS[1], Nondet.bytes(Nondet.LONG_VALUE));
        assert Nondet.same(t.put(Nondet.KEYS[1], new byte[0]).toMessage(), t.toMessage());
    }
}
