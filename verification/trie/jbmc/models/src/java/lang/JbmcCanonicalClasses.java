/*
 * JBMC environment model helper (not a JDK class): the canonical Class objects returned by the
 * java.lang.Object model's getClass(). Class.forName in JBMC's models library builds a Class whose
 * name is the given literal.
 */
package java.lang;

final class JbmcCanonicalClasses {
    static final Class<?> UINT24 = Class.forName("co.rsk.core.types.ints.Uint24");
    static final Class<?> UINT16 = Class.forName("co.rsk.core.types.ints.Uint16");
    static final Class<?> UINT8 = Class.forName("co.rsk.core.types.ints.Uint8");
    static final Class<?> KECCAK256 = Class.forName("co.rsk.crypto.Keccak256");
    static final Class<?> TRIE = Class.forName("co.rsk.trie.Trie");
    static final Class<?> DATAWORD = Class.forName("org.ethereum.vm.DataWord");
    static final Class<?> RSKADDRESS = Class.forName("co.rsk.core.RskAddress");
    static final Class<?> COIN = Class.forName("co.rsk.core.Coin");

    private JbmcCanonicalClasses() { }
}
