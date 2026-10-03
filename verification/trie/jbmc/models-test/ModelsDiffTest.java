import java.util.Arrays;
import java.util.Random;

/**
 * Randomized differential test: each JBMC environment model (compiled here under the package
 * prefix "jbmcmodel." so it can coexist with the real class on the JVM) against the real JDK 17
 * class. Compares every return value, the resulting array/buffer contents and the class of every
 * thrown exception. Usage: java ModelsDiffTest [iterations] [seed]
 */
public final class ModelsDiffTest {
    private static int checks = 0;

    public static void main(String[] args) {
        int iters = args.length > 0 ? Integer.parseInt(args[0]) : 200_000;
        long seed = args.length > 1 ? Long.parseLong(args[1]) : 20260926L;
        Random r = new Random(seed);
        staticValues();
        for (int i = 0; i < iters; i++) {
            if (i % 20 == 0) kvStore(r);
            arraycopy(r);
            mismatch(r);
            newLength(r);
            byteBuffer(r);
        }
        System.out.println("models-test OK: iterations=" + iters + " seed=" + seed + " checks=" + checks);
    }

    private static byte[] randomBytes(Random r, int len) {
        byte[] a = new byte[len];
        for (int i = 0; i < len; i++) {
            a[i] = (byte) (r.nextInt(4) - 1); // small alphabet so equal/mismatch both occur
        }
        return a;
    }

    private static void same(Object expected, Object actual, String what) {
        checks++;
        boolean eq = expected instanceof byte[] && actual instanceof byte[]
                ? Arrays.equals((byte[]) expected, (byte[]) actual)
                : java.util.Objects.equals(expected, actual);
        if (!eq) {
            throw new AssertionError(what + ": real=" + show(expected) + " model=" + show(actual));
        }
    }

    private static String show(Object o) {
        return o instanceof byte[] ? Arrays.toString((byte[]) o) : String.valueOf(o);
    }

    private interface Op { Object run() throws Throwable; }

    /** Result of an operation: its value, or the class name of the exception it threw. */
    private static Object outcome(Op op) {
        try {
            Object v = op.run();
            return v instanceof byte[] ? ((byte[]) v).clone() : v;
        } catch (Throwable t) {
            return "throws " + t.getClass().getName();
        }
    }

    private static void arraycopy(Random r) {
        byte[] s = r.nextInt(20) == 0 ? null : randomBytes(r, r.nextInt(9));
        boolean sameArray = s != null && r.nextInt(3) == 0;
        Object d;
        int kind = r.nextInt(20);
        if (sameArray) d = s;
        else if (kind == 0) d = null;
        else if (kind == 1) d = new int[r.nextInt(5)]; // ArrayStoreException path
        else d = randomBytes(r, r.nextInt(9));
        Object src = s;
        if (!sameArray && kind == 2) src = new Object(); // not an array
        int sp = r.nextInt(12) - 2, dp = r.nextInt(12) - 2, len = r.nextInt(12) - 2;
        if (r.nextInt(50) == 0) len = Integer.MAX_VALUE;
        if (r.nextInt(50) == 0) sp = Integer.MAX_VALUE;

        Object srcR = copyOf(src), dR = sameArray ? srcR : copyOf(d);
        Object srcM = copyOf(src), dM = sameArray ? srcM : copyOf(d);
        final Object fsR = srcR, fdR = dR, fsM = srcM, fdM = dM;
        final int fsp = sp, fdp = dp, flen = len;
        Object real = outcome(() -> { System.arraycopy(fsR, fsp, fdR, fdp, flen); return "ok"; });
        Object model = outcome(() -> { jbmcmodel.java.lang.System.arraycopy(fsM, fsp, fdM, fdp, flen); return "ok"; });
        same(real, model, "arraycopy outcome");
        if (dR instanceof byte[]) same(dR, dM, "arraycopy dest");
        if (srcR instanceof byte[]) same(srcR, srcM, "arraycopy src");
    }

    private static Object copyOf(Object o) {
        if (o instanceof byte[]) return ((byte[]) o).clone();
        if (o instanceof int[]) return ((int[]) o).clone();
        return o;
    }

    private static void mismatch(Random r) {
        int n = r.nextInt(9);
        byte[] a = randomBytes(r, n + r.nextInt(3));
        byte[] b = r.nextBoolean() ? Arrays.copyOf(a, n + r.nextInt(3)) : randomBytes(r, n + r.nextInt(3));
        if (r.nextBoolean() && n > 0) b[r.nextInt(n)] ^= 1;
        same(jdk.internal.util.ArraysSupport.mismatch(a, b, n),
             jbmcmodel.jdk.internal.util.ArraysSupport.mismatch(a, b, n), "mismatch");
    }

    /** models/static-values.json gives TrieKeyMapper these field values instead of running its
     *  static initialiser; they must equal what the real initialiser computes. */
    private static void staticValues() {
        try {
            Class<?> c = Class.forName("org.ethereum.db.TrieKeyMapper");
            same(11, c.getField("REMASC_ACCOUNT_KEY_SIZE").get(null), "REMASC_ACCOUNT_KEY_SIZE (value given in models/static-values.json)");
            String[] names = {"DOMAIN_PREFIX", "STORAGE_PREFIX", "CODE_PREFIX"};
            byte[][] vals = {{0x00}, {0x00}, {(byte) 0x80}};
            for (int i = 0; i < names.length; i++) {
                java.lang.reflect.Field f = c.getDeclaredField(names[i]);
                f.setAccessible(true);
                same(vals[i], f.get(null), names[i]);
            }
            Class<?> dw = Class.forName("org.ethereum.vm.DataWord");
            java.lang.reflect.Field zd = dw.getDeclaredField("ZERO_DATA");
            zd.setAccessible(true);
            same(new byte[32], zd.get(null), "DataWord.ZERO_DATA");
            byte[] one = new byte[32];
            one[31] = 1;
            same(new byte[32], dw.getMethod("getData").invoke(dw.getField("ZERO").get(null)), "DataWord.ZERO");
            same(one, dw.getMethod("getData").invoke(dw.getField("ONE").get(null)), "DataWord.ONE");
        } catch (ReflectiveOperationException e) {
            throw new AssertionError(e);
        }
    }

    /** jbmcenv.MemoryKeyValueDataSource against the real HashMapDB: random put/get/delete/close. */
    private static void kvStore(Random r) {
        org.ethereum.datasource.HashMapDB real = new org.ethereum.datasource.HashMapDB();
        jbmcenv.MemoryKeyValueDataSource model = new jbmcenv.MemoryKeyValueDataSource();
        int ops = 1 + r.nextInt(30);
        for (int k = 0; k < ops; k++) {
            byte[] key = r.nextInt(30) == 0 ? null : randomBytes(r, r.nextInt(3));
            int op = r.nextInt(r.nextInt(12) == 0 ? 4 : 3);
            Object x, y;
            if (op == 0) {
                byte[] value = r.nextInt(30) == 0 ? null : randomBytes(r, 1 + r.nextInt(2));
                x = outcome(() -> { byte[] p = real.put(key, value); return p == null ? "null" : p; });
                y = outcome(() -> { byte[] p = model.put(key, value); return p == null ? "null" : p; });
                if (model.size() >= jbmcenv.MemoryKeyValueDataSource.CAPACITY - 1) break;
            } else if (op == 1) {
                x = outcome(() -> { byte[] g = real.get(key); return g == null ? "null" : g; });
                y = outcome(() -> { byte[] g = model.get(key); return g == null ? "null" : g; });
            } else if (op == 2) {
                if (key == null) continue; // HashMapDB.delete(null) is not part of the modelled contract
                x = outcome(() -> { real.delete(key); return "ok"; });
                y = outcome(() -> { model.delete(key); return "ok"; });
            } else {
                real.close();
                model.close();
                x = "closed"; y = "closed";
            }
            same(x, y, "kv op " + op);
        }
    }

    private static void newLength(Random r) {
        int[] picks = {0, 1, 2, 16, 32, 1000, Integer.MAX_VALUE - 9, Integer.MAX_VALUE - 8, Integer.MAX_VALUE - 1, Integer.MAX_VALUE};
        int old = r.nextBoolean() ? r.nextInt(64) : picks[r.nextInt(picks.length)];
        int min0 = r.nextBoolean() ? 1 + r.nextInt(64) : picks[r.nextInt(picks.length)];
        int min = min0 <= 0 ? 1 : min0;
        int pref = r.nextBoolean() ? r.nextInt(64) : picks[r.nextInt(picks.length)];
        Object a = outcome(() -> jdk.internal.util.ArraysSupport.newLength(old, min, pref));
        Object b = outcome(() -> jbmcmodel.jdk.internal.util.ArraysSupport.newLength(old, min, pref));
        same(a, b, "newLength(" + old + "," + min + "," + pref + ")");
    }

    private static void byteBuffer(Random r) {
        java.nio.ByteBuffer real;
        jbmcmodel.java.nio.ByteBuffer model;
        if (r.nextBoolean()) {
            int cap = r.nextInt(10) - 1;
            Object a = outcome(() -> java.nio.ByteBuffer.allocate(cap));
            Object b = outcome(() -> jbmcmodel.java.nio.ByteBuffer.allocate(cap));
            if (a instanceof String || b instanceof String) { same(a, b, "allocate"); return; }
            real = (java.nio.ByteBuffer) a;
            model = (jbmcmodel.java.nio.ByteBuffer) b;
        } else {
            byte[] arr = r.nextInt(20) == 0 ? null : randomBytes(r, r.nextInt(9));
            byte[] arrM = arr == null ? null : arr.clone();
            Object a = outcome(() -> java.nio.ByteBuffer.wrap(arr));
            Object b = outcome(() -> jbmcmodel.java.nio.ByteBuffer.wrap(arrM));
            if (a instanceof String || b instanceof String) { same(a, b, "wrap"); return; }
            real = (java.nio.ByteBuffer) a;
            model = (jbmcmodel.java.nio.ByteBuffer) b;
        }
        int ops = 1 + r.nextInt(12);
        for (int k = 0; k < ops; k++) {
            int op = r.nextInt(10);
            Object x, y;
            switch (op) {
                case 0: x = outcome(real::get); y = outcome(model::get); break;
                case 1: { int i = r.nextInt(12) - 2; x = outcome(() -> real.get(i)); y = outcome(() -> model.get(i)); break; }
                case 2: {
                    byte[] d1 = r.nextInt(20) == 0 ? null : randomBytes(r, r.nextInt(6));
                    byte[] d2 = d1 == null ? null : d1.clone();
                    x = outcome(() -> { real.get(d1); return d1; });
                    y = outcome(() -> { model.get(d2); return d2; });
                    break;
                }
                case 3: { byte b = (byte) r.nextInt(256); x = outcome(() -> { real.put(b); return "ok"; }); y = outcome(() -> { model.put(b); return "ok"; }); break; }
                case 4: {
                    byte[] s1 = r.nextInt(20) == 0 ? null : randomBytes(r, r.nextInt(6));
                    x = outcome(() -> { real.put(s1); return "ok"; });
                    y = outcome(() -> { model.put(s1); return "ok"; });
                    break;
                }
                case 5: { short v = (short) r.nextInt(65536); x = outcome(() -> { real.putShort(v); return "ok"; }); y = outcome(() -> { model.putShort(v); return "ok"; }); break; }
                case 6: x = real.position(); y = model.position(); break;
                case 7: x = real.remaining(); y = model.remaining(); break;
                case 8: x = real.hasRemaining(); y = model.hasRemaining(); break;
                default: x = real.array().clone(); y = model.array().clone(); break;
            }
            same(x, y, "ByteBuffer op " + op);
            same(real.position(), model.position(), "ByteBuffer position after op " + op);
            same(real.array().clone(), model.array().clone(), "ByteBuffer contents after op " + op);
        }
    }
}
