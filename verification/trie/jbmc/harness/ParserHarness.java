import co.rsk.bitcoinj.core.VarInt;
import co.rsk.trie.Trie;
import org.cprover.CProver;
import org.ethereum.crypto.Keccak256Helper;

/**
 * Trie.fromMessage (co/rsk/trie/Trie.java:163-347) on crafted and malformed messages. Property
 * harnesses assert Java's behaviour on the reproducer inputs of spec/obligations.json (the same bytes
 * as differential/cases/reproducers.cases and the Lean *_rskip_counterexample theorems), generalised
 * to symbolic bytes where cheap; rskip-reading harnesses assert the canonical-parse reading
 * ("the parser rejects this input") and must FAIL.
 */
public class ParserHarness {
    static byte[] reencode(byte[] m) {
        return Trie.fromMessage(m, null).toMessage();
    }

    /** true iff fromMessage throws a RuntimeException (a rejection) on m. */
    static boolean rejects(byte[] m) {
        try {
            Trie.fromMessage(m, null).toMessage();
            return false;
        } catch (RuntimeException e) {
            return true;
        }
    }

    // ---- TRIE-PATH-04: padding bits of encodedSharedPath are ignored --------------------------

    /** Java: for every byte x, 50 00 x 01 (lshared = 1 bit) re-encodes to 50 00 (x & 80) 01. */
    public static void pathPaddingIgnored() {
        Keccak256Helper.consistent = false;
        byte x = CProver.nondetByte();
        assert Nondet.same(reencode(Nondet.b(0x50, 0x00, x, 0x01)), Nondet.b(0x50, 0x00, x & 0x80, 0x01));
        assert Nondet.same(reencode(Nondet.b(0x50, 0x00, 0xff, 0x01)), Nondet.b(0x50, 0x00, 0x80, 0x01));
    }

    public static void pathPaddingRskip() {
        Keccak256Helper.consistent = false;
        assert rejects(Nondet.b(0x50, 0x00, 0xff, 0x01));
    }

    // ---- TRIE-LSH-06: non-canonical lshared encodings ------------------------------------------

    static final byte[][] LSH06 = {
        Nondet.b(0x50, 0xff, 0x05, 0x00, 0x01),
        Nondet.b(0x50, 0xff, 0xfd, 0x05, 0x00, 0x00, 0x01),
        Nondet.b(0x50, 0xff, 0xff, 0x05, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x01),
        Nondet.b(0x50, 0xff, 0x00, 0x01),
    };
    static final byte[][] LSH06_OUT = {
        Nondet.b(0x50, 0x04, 0x00, 0x01), Nondet.b(0x50, 0x04, 0x00, 0x01),
        Nondet.b(0x50, 0x04, 0x00, 0x01), Nondet.b(0x40, 0x01),
    };

    /** Java: the four inputs parse and re-encode canonically (escape for a short length, non-minimal
     *  VarInt, VarInt 2^32+5 truncated to int 5, lshared 0 with the prefix flag set). */
    public static void lsharedNonCanonical() {
        Keccak256Helper.consistent = false;
        for (int i = 0; i < LSH06.length; i++) {
            assert Nondet.same(reencode(LSH06[i]), LSH06_OUT[i]);
        }
    }

    public static void lsharedNonCanonicalRskip() {
        Keccak256Helper.consistent = false;
        boolean allRejected = true;
        for (byte[] m : LSH06) {
            allRejected &= rejects(m);
        }
        assert allRejected;
    }

    // ---- TRIE-VARINT-03: non-minimal treeSize VarInt ------------------------------------------

    static final byte[] VARINT03 = Nondet.b(0x5a, 0x07, 0x00, 0x04, 0x50, 0x06, 0x00, 0x02, 0xfd, 0x04, 0x00, 0x01);

    public static void varintNonMinimal() {
        Keccak256Helper.consistent = false;
        assert Nondet.same(reencode(VARINT03), Nondet.b(0x5a, 0x07, 0x00, 0x04, 0x50, 0x06, 0x00, 0x02, 0x04, 0x01));
    }

    public static void varintNonMinimalRskip() {
        Keccak256Helper.consistent = false;
        assert rejects(VARINT03);
    }

    /**
     * TRIE-VARINT-02 (Trie.readVarInt): for every 64-bit v, a node whose treeSize field is
     * VarInt(v).encode() parses with getChildrenSize().value == v and the field is consumed exactly
     * (fromMessage throws if any byte remains, Trie.java:340-342).
     */
    public static void treeSizeVarInt() {
        Keccak256Helper.consistent = false;
        long v = CProver.nondetLong();
        byte[] m = Nondet.cat(Nondet.b(0x48), Nondet.bytes(32), new VarInt(v).encode());
        Trie t = Trie.fromMessage(m, null);
        assert t.getChildrenSize().value == v;
    }

    public static void treeSizeVarIntNegative() {
        Keccak256Helper.consistent = false;
        long v = CProver.nondetLong();
        byte[] m = Nondet.cat(Nondet.b(0x48), Nondet.bytes(32), new VarInt(v).encode());
        assert Trie.fromMessage(m, null).getChildrenSize().value < 253;
    }

    // ---- TRIE-NODE-02: version bits are not checked -------------------------------------------

    static final byte[][] NODE02 = {Nondet.b(0xc0, 0x01), Nondet.b(0x80, 0x01), Nondet.b(0x00), Nondet.b(0x01, 0x01)};
    static final byte[][] NODE02_OUT = {Nondet.b(0x40, 0x01), Nondet.b(0x40, 0x01), Nondet.b(0x40), Nondet.b(0x40, 0x01)};

    /** Java: versions 11, 10 and non-Orchid 00 are parsed as RSKIP107 nodes; for every flags byte f
     *  other than 02 with the low 6 bits zero, f 01 parses as a leaf with value 01. */
    public static void versionNotChecked() {
        Keccak256Helper.consistent = false;
        for (int i = 0; i < NODE02.length; i++) {
            assert Nondet.same(reencode(NODE02[i]), NODE02_OUT[i]);
        }
        int top = CProver.nondetInt();
        CProver.assume(top >= 0 && top <= 3);
        assert Nondet.same(reencode(Nondet.b(top << 6, 0x01)), Nondet.b(0x40, 0x01));
    }

    public static void versionNotCheckedRskip() {
        Keccak256Helper.consistent = false;
        assert rejects(NODE02[0]) && rejects(NODE02[1]) && rejects(NODE02[2]);
    }

    // ---- TRIE-NODE-10: no trailing bytes after the long-value fields ---------------------------

    /** Java: a long-value leaf 60 <32 bytes> 000021 followed by any extra byte is rejected with
     *  IllegalArgumentException; without the extra byte it parses. */
    public static void trailingBytesRejected() {
        Keccak256Helper.consistent = false;
        byte[] leaf = Nondet.cat(Nondet.b(0x60), Nondet.bytes(32), Nondet.b(0x00, 0x00, 0x21));
        assert Trie.fromMessage(leaf, null).getValueLength().intValue() == 33;
        boolean threw = false;
        try {
            Trie.fromMessage(Nondet.cat(leaf, Nondet.bytes(1)), null);
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        assert threw;
    }

    public static void trailingBytesRejectedNegative() {
        Keccak256Helper.consistent = false;
        byte[] leaf = Nondet.cat(Nondet.b(0x60), Nondet.bytes(32), Nondet.b(0x00, 0x00, 0x21), Nondet.bytes(1));
        Trie.fromMessage(leaf, null); // claims: parses (must FAIL with the uncaught exception)
    }

    // ---- TRIE-EMB-02: non-terminal embedded child ----------------------------------------------

    /** Java: 4a 22 [48 <32x11> 00] 00 (embedded child with a hash child) parses and re-encodes the
     *  child by hash: 48 keccak(48 <32x11> 00) 00. */
    public static void embeddedNonTerminal() {
        byte[] child = Nondet.cat(Nondet.b(0x48), Nondet.rep(32, 0x11), Nondet.b(0x00));
        byte[] m = Nondet.cat(Nondet.b(0x4a, 0x22), child, Nondet.b(0x00));
        assert Nondet.same(reencode(m), Nondet.cat(Nondet.b(0x48), Keccak256Helper.keccak256(child), Nondet.b(0x00)));
    }

    public static void embeddedNonTerminalRskip() {
        Keccak256Helper.consistent = false;
        byte[] child = Nondet.cat(Nondet.b(0x48), Nondet.rep(32, 0x11), Nondet.b(0x00));
        assert rejects(Nondet.cat(Nondet.b(0x4a, 0x22), child, Nondet.b(0x00)));
    }

    // ---- TRIE-VAL-05: non-canonical value encodings --------------------------------------------

    /** Java: 40 ++ 33x00 re-encodes as a long value 60 keccak(33x00) 000021; 60 ++ 32xaa ++ 000001
     *  parses with valueLength 1 and hasLongValue false; 60 ++ 32xaa ++ 000000 parses to the empty
     *  node (re-encoded 40). */
    public static void valueNonCanonical() {
        byte[] z33 = Nondet.rep(33, 0x00);
        assert Nondet.same(reencode(Nondet.cat(Nondet.b(0x40), z33)),
                Nondet.cat(Nondet.b(0x60), Keccak256Helper.keccak256(z33), Nondet.b(0x00, 0x00, 0x21)));
        Trie t = Trie.fromMessage(Nondet.cat(Nondet.b(0x60), Nondet.rep(32, 0xaa), Nondet.b(0, 0, 1)), null);
        assert t.getValueLength().intValue() == 1 && !t.hasLongValue();
        assert Nondet.same(reencode(Nondet.cat(Nondet.b(0x60), Nondet.rep(32, 0xaa), Nondet.b(0, 0, 0))), Nondet.b(0x40));
    }

    public static void valueNonCanonicalRskip() {
        Keccak256Helper.consistent = false;
        assert rejects(Nondet.cat(Nondet.b(0x40), Nondet.rep(33, 0x00)))
                && rejects(Nondet.cat(Nondet.b(0x60), Nondet.rep(32, 0xaa), Nondet.b(0, 0, 1)))
                && rejects(Nondet.cat(Nondet.b(0x60), Nondet.rep(32, 0xaa), Nondet.b(0, 0, 0)));
    }

    // ---- TRIE-SER-03: child flags -------------------------------------------------------------

    public static void childFlagsNotChecked() {
        Keccak256Helper.consistent = false;
        assert Nondet.same(reencode(Nondet.b(0x42, 0x01)), Nondet.b(0x40, 0x01));
        assert Nondet.same(reencode(Nondet.b(0x4a, 0x01, 0x40, 0x00, 0x01)), Nondet.b(0x40, 0x01));
    }

    public static void childFlagsNotCheckedRskip() {
        Keccak256Helper.consistent = false;
        assert rejects(Nondet.b(0x42, 0x01)) && rejects(Nondet.b(0x4a, 0x01, 0x40, 0x00, 0x01));
    }

    // ---- TRIE-SIZE-03: treeSize is not validated -----------------------------------------------

    static final byte[] SIZE03 = Nondet.b(0x5a, 0x07, 0x00, 0x04, 0x50, 0x06, 0x00, 0x02, 0x05, 0x01);

    /** Java: 5a070004500600020501 (treeSize 5) parses with getChildrenSize() == 5 and re-encodes
     *  unchanged; for every treeSize byte c < 0xfd the same holds. */
    public static void treeSizeNotValidated() {
        Keccak256Helper.consistent = false;
        Trie t = Trie.fromMessage(SIZE03, null);
        assert t.getChildrenSize().value == 5 && Nondet.same(t.toMessage(), SIZE03);
        int c = CProver.nondetInt();
        CProver.assume(c >= 0 && c < 0xfd);
        byte[] m = Nondet.b(0x5a, 0x07, 0x00, 0x04, 0x50, 0x06, 0x00, 0x02, c, 0x01);
        assert Trie.fromMessage(m, null).getChildrenSize().value == c;
    }

    /** rskip-reading: treeSize must equal TRIE-SIZE-01 on the children, i.e. 4 for this node. */
    public static void treeSizeNotValidatedRskip() {
        Keccak256Helper.consistent = false;
        assert Trie.fromMessage(SIZE03, null).getChildrenSize().value == 4;
    }

    // ---- TRIE-SER-05: malformed input --------------------------------------------------------

    /** Largest message length for parserTotal (every length 0..MAX_MALFORMED is checked). */
    static final int MAX_MALFORMED = 4;

    /**
     * TRIE-SER-05 (Java, bounded): for every byte string m of 0..MAX_MALFORMED bytes, fromMessage
     * terminates and either returns a Trie or throws a RuntimeException (run with
     * --throw-runtime-exceptions, so implicit exceptions are real exceptions; any other throwable
     * escapes and is reported by the uncaught-exception check).
     */
    public static void parserTotal() {
        Keccak256Helper.consistent = false;
        for (int n = 0; n <= MAX_MALFORMED; n++) {
            byte[] m = Nondet.bytes(n);
            try {
                Trie.fromMessage(m, null);
            } catch (RuntimeException e) {
                // rejection is fine
            }
        }
    }

    /** Negative control: claims every 2-byte message is rejected. */
    public static void parserTotalNegative() {
        Keccak256Helper.consistent = false;
        assert rejects(Nondet.bytes(2));
    }

    static final byte[] SER05 = Nondet.b(0x50, 0xff, 0xfe, 0xff, 0xff, 0xff, 0x7f);

    /** TRIE-SER-05 (Java): on 50 ff fe ffffff7f (lshared = 2^31-1) the parser asks the buffer for a
     *  268435456-byte field (the array it allocated) and then throws BufferUnderflowException. */
    public static void hugeLshared() {
        Keccak256Helper.consistent = false;
        jbmcenv.Observe.maxGetRequest = 0;
        boolean threw = false;
        try {
            Trie.fromMessage(SER05, null);
        } catch (java.nio.BufferUnderflowException e) {
            threw = true;
        }
        assert threw && jbmcenv.Observe.maxGetRequest == 268435456;
    }

    /** rskip-reading (O(|m|) memory): the parser never allocates a field larger than 64x the input. */
    public static void hugeLsharedRskip() {
        Keccak256Helper.consistent = false;
        jbmcenv.Observe.maxGetRequest = 0;
        try {
            Trie.fromMessage(SER05, null);
        } catch (RuntimeException e) {
            // either outcome
        }
        assert jbmcenv.Observe.maxGetRequest <= 64 * SER05.length;
    }
}
