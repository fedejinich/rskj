/*
 * JBMC environment model. Replaces: jdk.internal.util.ArraysSupport (JDK 17). Only
 * mismatch(byte[], byte[], int) and newLength(int, int, int) are provided. newLength is the JDK 17
 * source verbatim (growth policy used by java.io.ByteArrayOutputStream). mismatch: it is what the real JDK 17 java.util.Arrays.equals(byte[], byte[])
 * bytecode (used unmodified) calls. The real method is vectorised through jdk.internal.misc.Unsafe,
 * which JBMC cannot execute.
 *
 * Semantics (JDK 17 javadoc/contract): index of the first mismatching element within the first
 * `length` elements, or -1 if none. Callers in Arrays guarantee 0 <= length <= a.length, b.length.
 * Faithfulness is checked against the real method by jbmc/models-test.
 */
package jdk.internal.util;

public class ArraysSupport {
    private ArraysSupport() { }

    public static final int SOFT_MAX_ARRAY_LENGTH = Integer.MAX_VALUE - 8;

    public static int newLength(int oldLength, int minGrowth, int prefGrowth) {
        int prefLength = oldLength + Math.max(minGrowth, prefGrowth);
        if (0 < prefLength && prefLength <= SOFT_MAX_ARRAY_LENGTH) {
            return prefLength;
        }
        return hugeLength(oldLength, minGrowth);
    }

    private static int hugeLength(int oldLength, int minGrowth) {
        int minLength = oldLength + minGrowth;
        if (minLength < 0) {
            throw new OutOfMemoryError("Required array length is too large"); // JDK: message with the numbers
        } else if (minLength <= SOFT_MAX_ARRAY_LENGTH) {
            return SOFT_MAX_ARRAY_LENGTH;
        } else {
            return minLength;
        }
    }

    public static int mismatch(byte[] a, byte[] b, int length) {
        for (int i = 0; i < length; i++) {
            if (a[i] != b[i]) {
                return i;
            }
        }
        return -1;
    }
}
