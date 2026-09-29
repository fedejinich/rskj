/*
 * JBMC environment model. Replaces: java.lang.System (JDK 17), which has no JBMC model
 * (arraycopy is native). Only the members reached by the trie code are provided.
 *
 * arraycopy: implements the JDK specification of System.arraycopy for byte[] source/destination:
 * NullPointerException on null arrays; ArrayStoreException if exactly one side is a byte[]
 * (or either side is not an array); ArrayIndexOutOfBoundsException if length < 0, srcPos < 0,
 * destPos < 0, srcPos + length > src.length or destPos + length > dest.length (checked without
 * overflow); overlapping copies within one array behave as if through a temporary copy.
 * Any other array type is not modelled: reaching it is an assertion failure, never silent.
 * Faithfulness is checked against the real System.arraycopy by jbmc/models-test.
 *
 * exit: the trie code calls System.exit only from NodeStopper lambdas on "broken database"
 * paths. Reaching it is reported as an assertion failure and the path is cut.
 *
 * Why it cannot change trie behaviour: for byte[] it computes exactly what the JDK computes
 * (including exceptions); anything else fails loudly.
 */
package java.lang;

import org.cprover.CProver;

public final class System {
    private System() { }

    public static void arraycopy(Object src, int srcPos, Object dest, int destPos, int length) {
        if (src == null || dest == null) {
            throw new NullPointerException();
        }
        if (!(src instanceof byte[])) {
            if (!(dest instanceof byte[])) {
                assert false : "System model: only byte[] arraycopy is modelled";
                CProver.assume(false);
            }
            throw new ArrayStoreException("arraycopy: type mismatch");
        }
        if (!(dest instanceof byte[])) {
            throw new ArrayStoreException("arraycopy: type mismatch");
        }
        byte[] s = (byte[]) src;
        byte[] d = (byte[]) dest;
        if (length < 0 || srcPos < 0 || destPos < 0
                || srcPos > s.length - length || destPos > d.length - length) {
            throw new ArrayIndexOutOfBoundsException("arraycopy: out of bounds");
        }
        if (s == d && srcPos < destPos) {
            for (int i = length - 1; i >= 0; i--) {
                d[destPos + i] = s[srcPos + i];
            }
        } else {
            for (int i = 0; i < length; i++) {
                d[destPos + i] = s[srcPos + i];
            }
        }
    }

    public static void exit(int status) {
        assert false : "System model: System.exit reached";
        CProver.assume(false);
    }
}
