/*
 * JBMC environment model. Replaces: org.ethereum.crypto.Keccak256Helper
 * (rskj-core/src/main/java/org/ethereum/crypto/Keccak256Helper.java). Only the members the trie
 * code uses are provided: DEFAULT_SIZE, DEFAULT_SIZE_BYTES and keccak256(byte[]).
 *
 * Why: bit-precise Keccak-f[1600] is far beyond what bounded model checking can symbolically
 * execute, and even Trie's static initialiser hashes (Trie.EMPTY_HASH, Trie.java:75,1088-1090).
 * The verification treats Keccak-256 as an ideal opaque function (verification/trie/README.md).
 *
 * Model: a consistent random oracle. A table of (input, output) pairs is kept for the current
 * execution. An input equal (byte-wise) to a previous one returns the same output; a new input
 * gets a fresh nondeterministic 32-byte output, assumed distinct from every output handed out so
 * far (collision freedom on the inputs actually hashed). Every call returns a fresh copy, as the
 * real method returns a fresh array.
 *
 * Bound: at most MAX_ENTRIES distinct inputs per execution path. Exceeding it is an assertion
 * failure ("oracle table full"), never a silent assumption, so a too-small table shows up as
 * FAILURE rather than a vacuous SUCCESS.
 *
 * Unconstrained mode (harness opt-in, `Keccak256Helper.consistent = false` before the first hash):
 * every call returns fresh nondeterministic bytes, with no table. This over-approximates every hash
 * function, Keccak included, so a SUCCESS in this mode holds for real Keccak (and for any hash
 * function, even one with collisions). A FAILURE can be spurious when the property compares digests
 * computed by two separate calls on equal inputs (e.g. messages of two independently built tries
 * that embed child hashes); such properties use a consistent mode. It is used for properties that
 * do not depend on digest equality, because the consistent table is expensive once symbolic execution merges paths that
 * hash a different number of times (the table size becomes symbolic).
 *
 * Concrete-output mode (harness opt-in, `consistent = true; concreteOutputs = true`): the same
 * consistent table, but each fresh output is a concrete 32-byte value encoding the table index
 * (0xC5 0x7A index 0...), hence pairwise distinct. This is one particular collision-free assignment.
 * It is used only by harnesses whose code uses digests solely as opaque values (compared for equality,
 * copied into messages and store keys, never branched on bit by bit); for such code every
 * collision-free assignment gives an isomorphic execution, so the result carries over to all of them.
 * Keeping digests concrete avoids symbolic store lookups.
 *
 * Why it cannot change trie behaviour beyond the stated idealisation: the trie code only uses the
 * digest as an opaque value (stored, compared, serialised). Any property proved for every
 * collision-free assignment of digests holds for real Keccak on every input set where Keccak
 * has no collision. Properties that depend on concrete digest values (e.g. the exact EMPTY_HASH
 * constant) cannot be checked with this model and are left to the differential tests.
 */
package org.ethereum.crypto;

import org.cprover.CProver;

public class Keccak256Helper {
    public static final int DEFAULT_SIZE = 256;
    public static final int DEFAULT_SIZE_BYTES = DEFAULT_SIZE / 8;

    /** Oracle table capacity: distinct inputs hashed along one execution path. */
    public static final int MAX_ENTRIES = 16;

    private static final byte[][] INPUTS = new byte[MAX_ENTRIES][];
    private static final byte[][] OUTPUTS = new byte[MAX_ENTRIES][];
    private static int size = 0;

    /** true: consistent collision-free oracle (default); false: unconstrained (see header). */
    public static boolean consistent = true;

    /** With consistent: fresh outputs are concrete and distinct (see header). */
    public static boolean concreteOutputs = false;

    private Keccak256Helper() { }

    public static byte[] keccak256(byte[] message) {
        if (message == null) {
            throw new NullPointerException(); // as the real method (message.length)
        }
        if (!consistent) {
            return fresh();
        }
        for (int i = 0; i < size; i++) {
            if (sameBytes(INPUTS[i], message)) {
                return copy(OUTPUTS[i]);
            }
        }
        assert size < MAX_ENTRIES : "Keccak256Helper model: oracle table full";
        byte[] out;
        if (concreteOutputs) {
            out = new byte[DEFAULT_SIZE_BYTES];
            out[0] = (byte) 0xC5;
            out[1] = (byte) 0x7A;
            out[2] = (byte) size; // distinct per table entry
        } else {
            out = fresh();
            for (int i = 0; i < size; i++) {
                CProver.assume(!sameBytes(OUTPUTS[i], out));
            }
        }
        INPUTS[size] = copy(message);
        OUTPUTS[size] = out;
        size++;
        return copy(out);
    }

    /** Number of distinct inputs hashed so far (for harnesses). */
    public static int oracleSize() {
        return size;
    }

    /** A fresh array of 32 nondet bytes (concrete length, element-wise nondet). */
    private static byte[] fresh() {
        byte[] out = new byte[DEFAULT_SIZE_BYTES];
        for (int j = 0; j < DEFAULT_SIZE_BYTES; j++) {
            out[j] = CProver.nondetByte();
        }
        return out;
    }

    private static boolean sameBytes(byte[] a, byte[] b) {
        if (a.length != b.length) {
            return false;
        }
        for (int i = 0; i < a.length; i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }

    private static byte[] copy(byte[] a) {
        return a.clone();
    }
}
