import co.rsk.trie.MultiTrieStore;
import co.rsk.trie.NodeReference;
import co.rsk.trie.Trie;
import co.rsk.trie.TrieStoreImpl;
import jbmcenv.MemoryKeyValueDataSource;
import org.ethereum.crypto.Keccak256Helper;

/**
 * Trie stores on the real co.rsk.trie.TrieStoreImpl and MultiTrieStore, over the in-memory
 * KeyValueDataSource model (jbmcenv.MemoryKeyValueDataSource, differentially tested against
 * HashMapDB). Keccak is the consistent oracle with concrete distinct outputs (concreteOutputs):
 * store code uses digests only as keys and message bytes, see the Keccak256Helper model header.
 * Tries are built from the concrete key universe Nondet.KEYS with concrete values.
 */
public class StoreHarness {
    static byte[] k(byte[] x) {
        return Keccak256Helper.keccak256(x);
    }

    static Trie build(TrieStoreImpl s, int i, int j, boolean longValue) {
        byte[][] K = Nondet.KEYS;
        Trie t = new Trie(s).put(K[i], longValue ? Nondet.rep(33, 0x0c) : Nondet.b(0x0a));
        return j < 0 ? t : t.put(K[j], Nondet.b(0x0b));
    }

    /** TRIE-STORE-01: after save(t), retrieve(t.getHash()) is present, has t's message and hash and
     *  the same lookups, for 1- and 2-key tries over KEYS (one inline or long value). */
    public static void saveRetrieve() {
        Keccak256Helper.concreteOutputs = true;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            for (int j = -1; j < K.length; j += 4) {
                if (!Nondet.in2(j)) continue; // SplitHarness: one second key per part (oracle table size)
                for (boolean lv : new boolean[] {false, true}) {
                    TrieStoreImpl s = new TrieStoreImpl(new MemoryKeyValueDataSource());
                    Trie t = build(s, i, j, lv);
                    s.save(t);
                    Trie u = s.retrieve(t.getHash().getBytes()).get();
                    assert Nondet.same(u.toMessage(), t.toMessage()) && u.getHash().equals(t.getHash());
                    for (byte[] q : K) {
                        assert Nondet.same(u.get(q), t.get(q));
                    }
                }
            }
        }
    }

    public static void saveRetrieveNegative() {
        Keccak256Helper.concreteOutputs = true;
        TrieStoreImpl s = new TrieStoreImpl(new MemoryKeyValueDataSource());
        Trie t = build(s, 1, 2, false);
        s.save(t);
        assert !s.retrieve(t.getHash().getBytes()).isPresent();
    }

    /** Every entry h -> m of db satisfies h == keccak(m). */
    static boolean contentAddressed(MemoryKeyValueDataSource db) {
        boolean ok = true;
        for (int e = 0; e < db.size(); e++) {
            ok &= Nondet.same(db.keyAt(e), k(db.valueAt(e)));
        }
        return ok;
    }

    /** TRIE-STORE-02 (Java): after saving a non-empty trie every entry is content-addressed (node
     *  messages and long values); saving the empty trie writes keccak(80) -> 40. */
    public static void contentAddressedStore() {
        Keccak256Helper.concreteOutputs = true;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            for (int j = -1; j < K.length; j += 4) {
                if (!Nondet.in2(j)) continue; // SplitHarness: one second key per part (oracle table size)
                for (boolean lv : new boolean[] {false, true}) {
                    MemoryKeyValueDataSource db = new MemoryKeyValueDataSource();
                    TrieStoreImpl s = new TrieStoreImpl(db);
                    s.save(build(s, i, j, lv));
                    assert contentAddressed(db);
                }
            }
        }
        MemoryKeyValueDataSource db = new MemoryKeyValueDataSource();
        TrieStoreImpl s = new TrieStoreImpl(db);
        s.save(new Trie(s));
        assert db.size() == 1 && Nondet.same(db.keyAt(0), k(Nondet.b(0x80))) && Nondet.same(db.valueAt(0), Nondet.b(0x40));
    }

    /** TRIE-STORE-02 rskip-reading: every saved entry is content-addressed, the empty root included. */
    public static void contentAddressedStoreRskip() {
        Keccak256Helper.concreteOutputs = true;
        MemoryKeyValueDataSource db = new MemoryKeyValueDataSource();
        TrieStoreImpl s = new TrieStoreImpl(db);
        s.save(new Trie(s));
        assert contentAddressed(db);
    }

    static int expectedEntries(Trie n, boolean root) {
        int c = 0;
        if (root || !n.isEmbeddable()) {
            c++;
        }
        if (n.hasLongValue()) {
            c++;
        }
        NodeReference[] refs = {n.getLeft(), n.getRight()};
        for (NodeReference r : refs) {
            if (!r.isEmpty()) {
                c += expectedEntries(r.getNode().get(), false);
            }
        }
        return c;
    }

    static boolean stored(MemoryKeyValueDataSource db, byte[] m) {
        for (int e = 0; e < db.size(); e++) {
            if (Nondet.same(db.valueAt(e), m)) {
                return true;
            }
        }
        return false;
    }

    /**
     * TRIE-STORE-03 / TRIE-STORE-04: save writes one entry per non-embedded node (the root always)
     * plus one per long value, no entry holding an embedded child's message, and for every long value
     * retrieveValue(valueHash) == value with valueHash == keccak(value). Tries of 1..3 keys of KEYS.
     */
    public static void savedEntries() {
        Keccak256Helper.concreteOutputs = true;
        byte[][] K = Nondet.KEYS;
        for (int i = Nondet.LO; i < Math.min(Nondet.HI, K.length); i++) {
            for (int j = i + 1; j < K.length; j += 2) {
                if (!Nondet.in2(j)) continue; // SplitHarness: one second key per part
                for (boolean lv : new boolean[] {false, true}) {
                    MemoryKeyValueDataSource db = new MemoryKeyValueDataSource();
                    TrieStoreImpl s = new TrieStoreImpl(db);
                    Trie t = build(s, i, j, lv).put(K[(j + 3) % K.length], Nondet.b(0x0d));
                    s.save(t);
                    assert db.size() == expectedEntries(t, true);
                    NodeReference[] refs = {t.getLeft(), t.getRight()};
                    for (NodeReference r : refs) {
                        if (!r.isEmpty() && r.isEmbeddable()) {
                            assert !stored(db, r.getNode().get().toMessage());
                        }
                    }
                    Trie lvNode = t.find(K[i]);
                    if (lvNode != null && lvNode.hasLongValue()) {
                        byte[] vh = lvNode.getValueHash().getBytes();
                        assert Nondet.same(vh, k(lvNode.getValue()));
                        assert Nondet.same(s.retrieveValue(vh), lvNode.getValue());
                    }
                }
            }
        }
    }

    public static void savedEntriesNegative() {
        Keccak256Helper.concreteOutputs = true;
        MemoryKeyValueDataSource db = new MemoryKeyValueDataSource();
        TrieStoreImpl s = new TrieStoreImpl(db);
        s.save(build(s, 1, 2, true));
        assert db.size() == 1;
    }

    static final MemoryKeyValueDataSource[] EPOCH_DBS = new MemoryKeyValueDataSource[8];
    static int created = 0;

    static MultiTrieStore multi() {
        created = 0;
        return new MultiTrieStore(0, 3, name -> {
            MemoryKeyValueDataSource db = new MemoryKeyValueDataSource();
            EPOCH_DBS[created++] = db;
            return new TrieStoreImpl(db);
        }, epoch -> { });
    }

    /**
     * TRIE-STORE-05: MultiTrieStore.save / saveValue write only to the current epoch store (the first
     * created, epochs.get(0)); retrieveValue returns the newest epoch's entry when several have one.
     */
    public static void epochsWriteNewestReadNewest() {
        Keccak256Helper.concreteOutputs = true;
        MultiTrieStore m = multi();
        assert created == 3;
        Trie t = new Trie(m).put(Nondet.b(0x01), Nondet.b(0xaa)).put(Nondet.b(0x02), Nondet.rep(33, 0xbb));
        m.save(t);
        m.saveValue(Nondet.b(0x77));
        assert EPOCH_DBS[0].size() == 3 && EPOCH_DBS[1].size() == 0 && EPOCH_DBS[2].size() == 0;
        byte[] key = Nondet.rep(32, 0x33);
        EPOCH_DBS[2].put(key, Nondet.b(0x02));  // oldest epoch
        EPOCH_DBS[1].put(key, Nondet.b(0x01));  // newer epoch
        assert Nondet.same(m.retrieveValue(key), Nondet.b(0x01));
        EPOCH_DBS[0].put(key, Nondet.b(0x00));  // current epoch
        assert Nondet.same(m.retrieveValue(key), Nondet.b(0x00));
        assert m.retrieve(t.getHash().getBytes()).isPresent();
    }

    public static void epochsNegative() {
        Keccak256Helper.concreteOutputs = true;
        MultiTrieStore m = multi();
        m.saveValue(Nondet.b(0x77));
        assert EPOCH_DBS[1].size() == 1;
    }

    /** TRIE-STORE-06 (Java, reproducer store06): save {01: aa, 02: bb}; collect(root) three times:
     *  the root is retrievable after collects 1 and 2 and gone after collect 3 (nothing is copied:
     *  the retrieved root is marked saved, so save() skips it). */
    public static void collectLosesRoot() {
        Keccak256Helper.concreteOutputs = true;
        MultiTrieStore m = multi();
        Trie t = new Trie(m).put(Nondet.b(0x01), Nondet.b(0xaa)).put(Nondet.b(0x02), Nondet.b(0xbb));
        m.save(t);
        byte[] root = t.getHash().getBytes();
        m.collect(root);
        boolean p1 = m.retrieve(root).isPresent();
        m.collect(root);
        boolean p2 = m.retrieve(root).isPresent();
        m.collect(root);
        boolean p3 = m.retrieve(root).isPresent();
        assert p1 && p2 && !p3;
    }

    /** TRIE-STORE-06 rskip-reading: every node reachable from the kept root survives each collect. */
    public static void collectLosesRootRskip() {
        Keccak256Helper.concreteOutputs = true;
        MultiTrieStore m = multi();
        Trie t = new Trie(m).put(Nondet.b(0x01), Nondet.b(0xaa)).put(Nondet.b(0x02), Nondet.b(0xbb));
        m.save(t);
        byte[] root = t.getHash().getBytes();
        boolean all = true;
        for (int c = 0; c < 3; c++) {
            m.collect(root);
            all &= m.retrieve(root).isPresent();
        }
        assert all;
    }

    static final byte[] H04 = Nondet.b(0x19, 0x65, 0x50, 0xc4, 0xc2, 0x1e, 0xd1, 0xdb, 0x87, 0x31, 0xb6, 0x99,
            0xb8, 0x1b, 0x52, 0xa8, 0x3e, 0xa6, 0xf0, 0x8d, 0x4b, 0x99, 0x06, 0x7f, 0x04, 0x59, 0xdc, 0x44, 0x79,
            0x6f, 0x9a, 0x8b);
    static final byte[] C04 = Nondet.b(0x50, 0x06, 0x00, 0x01);

    static byte[] p04() {
        return Nondet.cat(Nondet.b(0x48), H04, Nondet.b(0x04));
    }

    static TrieStoreImpl store04() {
        MemoryKeyValueDataSource db = new MemoryKeyValueDataSource();
        db.put(H04, C04);  // repro-hash-04: raw 196550c4... -> 50060001
        return new TrieStoreImpl(db);
    }

    /**
     * TRIE-HASH-04 (Java, reproducer repro-hash-04-*): a fresh parse of P = 48 H 04 hashes to
     * keccak(P) with message P; after get(00) loads the small child C, toMessage() is
     * 4a 04 50060001 04 (child now embedded) and getHash() is keccak of that message.
     */
    public static void hashDependsOnLoading() {
        Trie unloaded = Trie.fromMessage(p04(), store04());
        assert Nondet.same(unloaded.toMessage(), p04());
        assert Nondet.same(unloaded.getHash().getBytes(), k(p04()));
        Trie loaded = Trie.fromMessage(p04(), store04());
        assert Nondet.same(loaded.get(Nondet.b(0x00)), Nondet.b(0x01));
        byte[] reencoded = Nondet.b(0x4a, 0x04, 0x50, 0x06, 0x00, 0x01, 0x04);
        assert Nondet.same(loaded.toMessage(), reencoded);
        assert Nondet.same(loaded.getHash().getBytes(), k(reencoded));
    }

    /** TRIE-HASH-04 rskip-reading: the hash does not depend on what was loaded first. */
    public static void hashDependsOnLoadingRskip() {
        Trie unloaded = Trie.fromMessage(p04(), store04());
        Trie loaded = Trie.fromMessage(p04(), store04());
        loaded.get(Nondet.b(0x00));
        assert unloaded.getHash().equals(loaded.getHash());
    }

    /**
     * TRIE-VAL-06 (Java): a long-value leaf 60 H 000021 parsed from a store mapping H to any 33-byte
     * v' returns v' from getValue(), whether or not keccak(v') == H.
     */
    public static void lazyValueNotChecked() {
        Keccak256Helper.concreteOutputs = true;
        byte[] h = Nondet.rep(32, 0x11);
        byte[] v = Nondet.bytes(33);
        MemoryKeyValueDataSource db = new MemoryKeyValueDataSource();
        db.put(h, v);
        Trie t = Trie.fromMessage(Nondet.cat(Nondet.b(0x60), h, Nondet.b(0x00, 0x00, 0x21)), new TrieStoreImpl(db));
        assert Nondet.same(t.getValue(), v);
    }

    /** TRIE-VAL-06 rskip-reading: the lazily retrieved value hashes to the stored valueHash. */
    public static void lazyValueNotCheckedRskip() {
        Keccak256Helper.concreteOutputs = true;
        byte[] h = Nondet.rep(32, 0x11);
        MemoryKeyValueDataSource db = new MemoryKeyValueDataSource();
        db.put(h, Nondet.rep(33, 0xab));
        Trie t = Trie.fromMessage(Nondet.cat(Nondet.b(0x60), h, Nondet.b(0x00, 0x00, 0x21)), new TrieStoreImpl(db));
        assert Nondet.same(k(t.getValue()), t.getValueHash().getBytes());
    }
}
