import co.rsk.trie.PathEncoder;
import org.cprover.CProver;
import org.ethereum.crypto.Keccak256Helper;

/**
 * Sanity checks of the JBMC environment itself: the Keccak oracle is consistent and collision-free
 * on the inputs it sees, and an exception escaping a harness is reported as a FAILURE.
 */
public class ModelSanityHarness {
    public static void keccakOracle() {
        byte[] a = Nondet.bytes(Nondet.intIn(0, 3) == 0 ? 0 : 3);
        byte[] b = Nondet.bytes(3);
        byte[] ha = Keccak256Helper.keccak256(a);
        byte[] hb = Keccak256Helper.keccak256(b);
        byte[] ha2 = Keccak256Helper.keccak256(a.clone());
        assert ha.length == 32 && hb.length == 32;
        assert Nondet.same(ha, ha2);                             // consistent
        assert Nondet.same(ha, hb) == Nondet.same(a, b);         // injective on seen inputs
        ha[0] ^= 1;                                              // callers get fresh copies
        assert Nondet.same(Keccak256Helper.keccak256(a), ha2);
    }

    /** Negative control: claims two different inputs can collide (must FAIL: they cannot). */
    public static void keccakOracleNegative() {
        byte[] a = Nondet.bytes(2);
        byte[] b = Nondet.bytes(2);
        CProver.assume(!Nondet.same(a, b));
        boolean collide = Nondet.same(Keccak256Helper.keccak256(a), Keccak256Helper.keccak256(b));
        assert collide;
    }

    /** Must FAIL (array-index check): an implicit runtime exception inside real rskj code. */
    public static void uncaughtExceptionIsFailure() {
        PathEncoder.decode(new byte[0], Nondet.intIn(0, 8));
    }

    /** Must FAIL ("no uncaught exception"): an explicit throw escaping from real rskj code. */
    public static void thrownExceptionIsFailure() {
        PathEncoder.encode(Nondet.intIn(0, 1) == 0 ? null : new byte[1]);
    }
}
