/*
 * JBMC environment model. Replaces: java.nio.ByteBuffer / java.nio.HeapByteBuffer (JDK 17).
 *
 * Why: the real classes go through java.nio.Buffer's static initialiser (jdk.internal.misc.Unsafe,
 * ScopedMemoryAccess, SharedSecrets) and Unsafe-based accessors, which JBMC cannot execute.
 *
 * Scope: a heap buffer created by allocate(int) or wrap(byte[]) (offset 0, big-endian, writable,
 * no mark), with exactly the members the trie code uses (javap of co.rsk.trie.*): allocate, wrap,
 * get(), get(int), get(byte[]), put(byte), put(byte[]), putShort, position(), remaining(),
 * hasRemaining(), array(). Behaviour, including the exception thrown on every misuse
 * (IllegalArgumentException, NullPointerException, BufferUnderflowException,
 * BufferOverflowException, IndexOutOfBoundsException), follows the JDK 17 HeapByteBuffer code.
 * The exception classes are the real JDK 17 ones.
 *
 * Why it cannot change trie behaviour: it computes the same values and throws the same exception
 * classes as the real heap buffer for every call it provides; this is checked by a randomized
 * differential test against the real JDK class (jbmc/models-test). Members it does not provide
 * have no body in JBMC and are listed by the stub audit.
 */
package java.nio;

public class ByteBuffer {
    private final byte[] hb;
    private int position;
    private final int limit;

    private ByteBuffer(byte[] hb) {
        this.hb = hb;
        this.position = 0;
        this.limit = hb.length;
    }

    public static ByteBuffer allocate(int capacity) {
        if (capacity < 0) {
            throw new IllegalArgumentException("capacity < 0");
        }
        return new ByteBuffer(new byte[capacity]);
    }

    public static ByteBuffer wrap(byte[] array) {
        if (array == null) {
            throw new NullPointerException();
        }
        return new ByteBuffer(array);
    }

    public byte get() {
        if (position >= limit) {
            throw new BufferUnderflowException();
        }
        return hb[position++];
    }

    public byte get(int index) {
        if (index < 0 || index >= limit) {
            throw new IndexOutOfBoundsException();
        }
        return hb[index];
    }

    public ByteBuffer get(byte[] dst) {
        int length = dst.length;
        if (length > jbmcenv.Observe.maxGetRequest) { // observation hook only (jbmcenv.Observe)
            jbmcenv.Observe.maxGetRequest = length;
        }
        if (length > limit - position) {
            throw new BufferUnderflowException();
        }
        for (int i = 0; i < length; i++) {
            dst[i] = hb[position + i];
        }
        position += length;
        return this;
    }

    public ByteBuffer put(byte b) {
        if (position >= limit) {
            throw new BufferOverflowException();
        }
        hb[position++] = b;
        return this;
    }

    public ByteBuffer put(byte[] src) {
        int length = src.length;
        if (length > limit - position) {
            throw new BufferOverflowException();
        }
        for (int i = 0; i < length; i++) {
            hb[position + i] = src[i];
        }
        position += length;
        return this;
    }

    public ByteBuffer putShort(short value) {
        if (limit - position < 2) {
            throw new BufferOverflowException();
        }
        hb[position] = (byte) (value >> 8);
        hb[position + 1] = (byte) value;
        position += 2;
        return this;
    }

    public int position() {
        return position;
    }

    public int remaining() {
        int rem = limit - position;
        return rem > 0 ? rem : 0;
    }

    public boolean hasRemaining() {
        return position < limit;
    }

    public byte[] array() {
        return hb;
    }
}
