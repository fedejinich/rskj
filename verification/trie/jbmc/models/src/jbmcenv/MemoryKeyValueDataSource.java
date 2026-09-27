/*
 * JBMC environment model (not a replacement of an rskj class): an in-memory KeyValueDataSource used
 * as the backing store of the real TrieStoreImpl / MultiTrieStore in store harnesses, in place of
 * org.ethereum.datasource.HashMapDB (whose ConcurrentHashMap JBMC cannot execute).
 *
 * Semantics follow HashMapDB exactly for the members the trie stores use: entries are keyed by the
 * key's content (HashMapDB wraps the key in ByteArrayWrapper, no copy), values are stored and
 * returned by reference (no copy), put returns the previous value or null, get/put reject null
 * with NullPointerException (Objects.requireNonNull), delete removes, close() clears (HashMapDB's
 * default clearOnClose = true), flush() does nothing. keys/keyIterator/updateBatch are not used by
 * TrieStoreImpl/MultiTrieStore and throw UnsupportedOperationException (loud, never silent).
 * Capacity is bounded by CAPACITY entries; exceeding it is an assertion failure.
 * Faithfulness: randomized differential test against the real HashMapDB, models-test/run.sh.
 */
package jbmcenv;

import java.util.Map;
import java.util.Objects;
import java.util.Set;
import org.ethereum.datasource.DataSourceKeyIterator;
import org.ethereum.datasource.KeyValueDataSource;
import org.ethereum.db.ByteArrayWrapper;

public class MemoryKeyValueDataSource implements KeyValueDataSource {
    public static final int CAPACITY = 16;

    private final byte[][] keys = new byte[CAPACITY][];
    private final byte[][] values = new byte[CAPACITY][];
    private int size = 0;

    private int indexOf(byte[] key) {
        for (int i = 0; i < size; i++) {
            if (sameBytes(keys[i], key)) {
                return i;
            }
        }
        return -1;
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

    @Override
    public byte[] get(byte[] key) {
        Objects.requireNonNull(key);
        int i = indexOf(key);
        return i < 0 ? null : values[i];
    }

    @Override
    public byte[] put(byte[] key, byte[] value) {
        Objects.requireNonNull(key);
        Objects.requireNonNull(value);
        int i = indexOf(key);
        if (i >= 0) {
            byte[] old = values[i];
            values[i] = value;
            return old;
        }
        assert size < CAPACITY : "MemoryKeyValueDataSource model: capacity exceeded";
        keys[size] = key;
        values[size] = value;
        size++;
        return null;
    }

    @Override
    public void delete(byte[] key) {
        int i = indexOf(key);
        if (i >= 0) {
            size--;
            keys[i] = keys[size];
            values[i] = values[size];
            keys[size] = null;
            values[size] = null;
        }
    }

    /** Number of entries (for harnesses). */
    public int size() {
        return size;
    }

    /** i-th entry key / value, 0 <= i < size() (for harnesses). */
    public byte[] keyAt(int i) {
        return keys[i];
    }

    public byte[] valueAt(int i) {
        return values[i];
    }

    @Override
    public Set<ByteArrayWrapper> keys() {
        throw new UnsupportedOperationException("not modelled");
    }

    @Override
    public DataSourceKeyIterator keyIterator() {
        throw new UnsupportedOperationException("not modelled");
    }

    @Override
    public void updateBatch(Map<ByteArrayWrapper, byte[]> entriesToUpdate, Set<ByteArrayWrapper> keysToRemove) {
        throw new UnsupportedOperationException("not modelled");
    }

    @Override
    public void flush() {
    }

    @Override
    public String getName() {
        return "in-memory";
    }

    @Override
    public void init() {
        size = 0;
    }

    @Override
    public boolean isAlive() {
        return true;
    }

    @Override
    public void close() {
        for (int i = 0; i < size; i++) {
            keys[i] = null;
            values[i] = null;
        }
        size = 0;
    }
}
