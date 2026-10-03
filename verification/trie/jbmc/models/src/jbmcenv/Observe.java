/*
 * JBMC environment observation hooks (not a replacement of any class). Written by environment
 * models, read by harnesses; they never influence the modelled behaviour.
 */
package jbmcenv;

public final class Observe {
    /** Largest destination length ever passed to the java.nio.ByteBuffer model's get(byte[]). */
    public static int maxGetRequest = 0;

    private Observe() { }
}
