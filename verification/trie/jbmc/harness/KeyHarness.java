import co.rsk.core.RskAddress;
import co.rsk.db.MutableTrieImpl;
import co.rsk.trie.Trie;
import co.rsk.trie.TrieStoreImpl;
import jbmcenv.MemoryKeyValueDataSource;
import org.cprover.CProver;
import org.ethereum.crypto.Keccak256Helper;
import org.ethereum.db.MutableRepository;
import org.ethereum.db.TrieKeyMapper;
import org.ethereum.util.ByteUtil;
import org.ethereum.vm.DataWord;

/**
 * Key mapping (RSKIP108 / RSKIP112) on the real org.ethereum.db.TrieKeyMapper (with its HashMap
 * cache, real JDK 17 bytecode; expected values use a fresh mapper so each call is a cache miss, the
 * cache-hit path is checked by accountKeyCached), RskAddress, DataWord, ByteUtil and MutableRepository. Keccak is the
 * consistent collision-free oracle (Keccak256Helper model): the harness compares key bytes with
 * Keccak256Helper.keccak256 of the same input, which the oracle answers consistently.
 */
public class KeyHarness {
    static byte[] h10(byte[] x) {
        return Nondet.slice(Keccak256Helper.keccak256(x), 0, 10);
    }

    /** TRIE-KEY-01: getAccountKey(a) == 00 ++ keccak(a)[0..10) ++ a, 31 bytes, for every address a. */
    public static void accountKey() {
        byte[] a = Nondet.bytes(20);
        TrieKeyMapper m = new TrieKeyMapper();
        byte[] k = m.getAccountKey(new RskAddress(a));
        assert Nondet.same(k, Nondet.cat(Nondet.b(0), h10(a), a));
    }

    /** TRIE-KEY-01, cache path: a second getAccountKey for an equal address (HashMap hit, real JDK
     *  HashMap) returns the same key; address with 1 symbolic byte (the hash-code multiplication
     *  chain over 20 symbolic bytes is too hard for the solver within minutes). */
    public static void accountKeyCached() {
        byte[] a = Nondet.cat(Nondet.bytes(1), Nondet.rep(19, 0x11));
        TrieKeyMapper m = new TrieKeyMapper();
        byte[] k = m.getAccountKey(new RskAddress(a));
        assert Nondet.same(m.getAccountKey(new RskAddress(a)), k);
        assert Nondet.same(k, Nondet.cat(Nondet.b(0), h10(a), a));
    }

    public static void accountKeyNegative() {
        byte[] a = Nondet.bytes(20);
        byte[] k = new TrieKeyMapper().getAccountKey(new RskAddress(a));
        assert k[1] == a[0];
    }

    /** TRIE-KEY-02 (Java): secureKeyPrefix(x) is exactly keccak(x)[0..10), for x of 0..32 bytes. */
    public static void securePrefix() {
        TrieKeyMapper m = new TrieKeyMapper();
        for (int n : new int[] {0, 1, 20, 32}) {
            byte[] x = Nondet.bytes(n);
            byte[] p = m.secureKeyPrefix(x);
            assert p.length == TrieKeyMapper.SECURE_KEY_SIZE && p.length == 10;
            assert Nondet.same(p, h10(x));
        }
    }

    /** TRIE-KEY-02 rskip-reading: the literal half-open slice [0:9] gives a 9-byte prefix. */
    public static void securePrefixRskip() {
        byte[] x = Nondet.bytes(20);
        assert new TrieKeyMapper().secureKeyPrefix(x).length == 9;
    }

    /** TRIE-KEY-03: getCodeKey(a) == getAccountKey(a) ++ 80. */
    public static void codeKey() {
        byte[] a = Nondet.bytes(20);
        TrieKeyMapper m = new TrieKeyMapper();
        RskAddress addr = new RskAddress(a);
        assert Nondet.same(m.getCodeKey(addr), Nondet.cat(new TrieKeyMapper().getAccountKey(addr), Nondet.b(0x80)));
    }

    public static void codeKeyNegative() {
        RskAddress addr = new RskAddress(Nondet.bytes(20));
        assert new TrieKeyMapper().getCodeKey(addr)[31] == 0;
    }

    /** TRIE-KEY-04: getAccountStoragePrefixKey(a) == getAccountKey(a) ++ 00. */
    public static void storagePrefixKey() {
        byte[] a = Nondet.bytes(20);
        TrieKeyMapper m = new TrieKeyMapper();
        RskAddress addr = new RskAddress(a);
        assert Nondet.same(m.getAccountStoragePrefixKey(addr), Nondet.cat(new TrieKeyMapper().getAccountKey(addr), Nondet.b(0)));
    }

    public static void storagePrefixKeyNegative() {
        RskAddress addr = new RskAddress(Nondet.bytes(20));
        assert new TrieKeyMapper().getAccountStoragePrefixKey(addr).length == 31;
    }

    /** Leading-zero counts of the 32-byte storage words enumerated by the storage-key harnesses. */
    static final int[] ZEROS = {0, 1, 16, 31, 32};

    /** Values used for the first non-zero byte of a storage word (smallest, top bit, largest). */
    static final int[] FIRST_BYTES = {0x01, 0x80, 0xff};

    /**
     * A 32-byte word with exactly z leading zero bytes (z == 32: the zero word): z zero bytes, the
     * concrete non-zero byte fb, then 31-z symbolic bytes. The zero prefix and fb are concrete so that
     * stripLeadingZeroes' result length is concrete for symbolic execution (a symbolic first non-zero
     * byte left it symbolic and the runs did not finish).
     */
    static byte[] word(int z, int fb) {
        if (z == 32) {
            return new byte[32];
        }
        return Nondet.cat(Nondet.rep(z, 0), Nondet.b(fb), Nondet.bytes(31 - z));
    }

    static byte[] trimmed(byte[] s, int z) {
        return z == 32 ? Nondet.b(0) : Nondet.slice(s, z, 32);
    }

    /**
     * TRIE-KEY-06 and TRIE-KEY-08: getAccountStorageKey(a, s) == storagePrefixKey(a) ++
     * keccak(s)[0..10) ++ trim(s), and ByteUtil.stripLeadingZeroes implements trim, for every address
     * and every 32-byte word with z leading zero bytes, z in ZEROS.
     */
    public static void storageKey() {
        byte[] a = Nondet.bytes(20);
        TrieKeyMapper m = new TrieKeyMapper();
        RskAddress addr = new RskAddress(a);
        for (int zi = Nondet.LO; zi < Math.min(Nondet.HI, ZEROS.length); zi++) {
          int z = ZEROS[zi];
          for (int fi = Nondet.LO2; fi < Math.min(Nondet.HI2, FIRST_BYTES.length); fi++) {
            int fb = FIRST_BYTES[fi];
            byte[] s = word(z, fb);
            assert Nondet.same(ByteUtil.stripLeadingZeroes(s), trimmed(s, z));
            byte[] k = new TrieKeyMapper().getAccountStorageKey(addr, DataWord.valueOf(s));
            assert Nondet.same(k, Nondet.cat(new TrieKeyMapper().getAccountStoragePrefixKey(addr), h10(s), trimmed(s, z)));
          }
        }
    }

    public static void storageKeyNegative() {
        RskAddress addr = new RskAddress(Nondet.bytes(20));
        TrieKeyMapper m = new TrieKeyMapper();
        // one reachable case is enough for a negative control: z = 0 gives a 74-byte key
        assert new TrieKeyMapper().getAccountStorageKey(addr, DataWord.valueOf(word(0, 0x80))).length == 43;
    }

    /** TRIE-KEY-08 on its own: stripLeadingZeroes for every z in 0..32. */
    public static void stripLeadingZeroes() {
        for (int z = Nondet.LO; z <= Math.min(Nondet.HI - 1, 32); z++) {
            for (int fb : FIRST_BYTES) {
                byte[] s = word(z, fb);
                assert Nondet.same(ByteUtil.stripLeadingZeroes(s), trimmed(s, z));
            }
        }
    }

    public static void stripLeadingZeroesNegative() {
        // one reachable case is enough for a negative control: the zero word strips to [00], not []
        assert ByteUtil.stripLeadingZeroes(word(32, 0x01)).length == 0;
    }

    /** TRIE-KEY-07 (Java): the storage prefix is keccak of the full 32-byte word (slot 1). */
    public static void storagePrefixHashInput() {
        byte[] a = Nondet.bytes(20);
        byte[] s = Nondet.cat(Nondet.rep(31, 0), Nondet.b(1));
        byte[] k = new TrieKeyMapper().getAccountStorageKey(new RskAddress(a), DataWord.valueOf(s));
        assert Nondet.same(Nondet.slice(k, 32, 42), h10(s));
    }

    /** TRIE-KEY-07 rskip-reading (b): the prefix is keccak(trimmed_storage_address) = keccak(01). */
    public static void storagePrefixHashInputRskip() {
        byte[] a = Nondet.bytes(20);
        byte[] s = Nondet.cat(Nondet.rep(31, 0), Nondet.b(1));
        byte[] k = new TrieKeyMapper().getAccountStorageKey(new RskAddress(a), DataWord.valueOf(s));
        assert Nondet.same(Nondet.slice(k, 32, 42), h10(Nondet.b(1)));
    }

    /**
     * TRIE-KEY-09: getAccountKey is injective; account (31 B), code (32 B, last 80), storage-prefix
     * (32 B, last 00) and storage keys (43..74 B) never coincide; getAccountStorageKey(a,s) ==
     * getAccountStorageKey(a',s') implies a == a' and s == s' (words with z, z' in ZEROS).
     */
    public static void injective() {
        byte[] a1 = Nondet.bytes(20), a2 = Nondet.bytes(20);
        RskAddress x = new RskAddress(a1), y = new RskAddress(a2);
        if (Nondet.same(new TrieKeyMapper().getAccountKey(x), new TrieKeyMapper().getAccountKey(y))) {
            assert Nondet.same(a1, a2);
        }
        byte[] ck = new TrieKeyMapper().getCodeKey(x), pk = new TrieKeyMapper().getAccountStoragePrefixKey(y);
        assert new TrieKeyMapper().getAccountKey(x).length == 31 && ck.length == 32 && pk.length == 32;
        assert ck[31] == (byte) 0x80 && pk[31] == 0 && !Nondet.same(ck, pk);
        for (int zi = Nondet.LO; zi < Math.min(Nondet.HI, ZEROS.length); zi++) {
            int z1 = ZEROS[zi];
            byte[] s1 = word(z1, 0x80);
            byte[] k1 = new TrieKeyMapper().getAccountStorageKey(x, DataWord.valueOf(s1));
            assert k1.length >= 43 && k1.length <= 74;
            for (int z2i = Nondet.LO2; z2i < Math.min(Nondet.HI2, ZEROS.length); z2i++) {
                int z2 = ZEROS[z2i];
                byte[] s2 = word(z2, 0x80);
                if (Nondet.same(k1, new TrieKeyMapper().getAccountStorageKey(y, DataWord.valueOf(s2)))) {
                    assert Nondet.same(a1, a2) && Nondet.same(s1, s2);
                }
            }
        }
    }

    public static void injectiveNegative() {
        byte[] a1 = Nondet.bytes(20), a2 = Nondet.bytes(20);
        assert Nondet.same(new TrieKeyMapper().getAccountKey(new RskAddress(a1)),
                new TrieKeyMapper().getAccountKey(new RskAddress(a2)));
    }

    static MutableRepository repository() {
        TrieStoreImpl s1 = new TrieStoreImpl(new MemoryKeyValueDataSource());
        TrieStoreImpl s2 = new TrieStoreImpl(new MemoryKeyValueDataSource());
        return new MutableRepository(new MutableTrieImpl(s1, new Trie(s1)), new MutableTrieImpl(s2, new Trie(s2)));
    }

    /**
     * TRIE-KEY-05 / TRIE-KEY-10 (Java): MutableRepository.setupContract(a) (the step addStorageBytes
     * runs for a new contract, MutableRepository.java:258-264) stores exactly [0x01] at
     * getAccountStoragePrefixKey(a), for every address a.
     */
    public static void storageRootValue() {
        byte[] a = Nondet.bytes(20);
        MutableRepository r = repository();
        RskAddress addr = new RskAddress(a);
        r.setupContract(addr);
        byte[] v = r.getTrie().get(new TrieKeyMapper().getAccountStoragePrefixKey(addr));
        assert Nondet.same(v, Nondet.b(0x01));
    }

    /** TRIE-KEY-05 rskip-reading: RSKIP108 table: the storage-root placeholder value is 0x00. */
    public static void storageRootValueRskip() {
        byte[] a = Nondet.bytes(20);
        MutableRepository r = repository();
        RskAddress addr = new RskAddress(a);
        r.setupContract(addr);
        assert Nondet.same(r.getTrie().get(new TrieKeyMapper().getAccountStoragePrefixKey(addr)), Nondet.b(0x00));
    }

    /** TRIE-KEY-10 rskip-reading: RSKIP112: a storage-root value starts with the type byte 'R'. */
    public static void storageRootTypeByteRskip() {
        byte[] a = Nondet.bytes(20);
        MutableRepository r = repository();
        RskAddress addr = new RskAddress(a);
        r.setupContract(addr);
        assert r.getTrie().get(new TrieKeyMapper().getAccountStoragePrefixKey(addr))[0] == 'R';
    }

    /** TRIE-KEY-10 (Java): the trie stores a value exactly as given, whatever its first byte. */
    public static void valuesStoredAsGiven() {
        Keccak256Helper.consistent = false;
        for (byte[] k : Nondet.KEYS) {
            for (int n = 1; n <= 3; n++) {
                byte[] v = Nondet.bytes(n);
                assert Nondet.same(new Trie().put(k, v).get(k), v);
            }
        }
    }

    /** TRIE-KEY-10 rskip-reading at trie level: every stored value starts with 'A', 'S', 'R' or 'D'. */
    public static void valueTypeByteRskip() {
        Keccak256Helper.consistent = false;
        byte[] v = Nondet.bytes(2);
        byte first = new Trie().put(Nondet.b(1), v).get(Nondet.b(1))[0];
        assert first == 'A' || first == 'S' || first == 'R' || first == 'D';
    }
}
