package co.rsk.trie;

import org.junit.Test;

import static org.bouncycastle.util.encoders.Hex.decode;

public class TrieUpdateRentTest {

    @Test
    public void updateRentTimestampBasicTest() {

    }

    /**
     * @return the following trie, just with leafs with values
     *
     *       .
     *      / \
     *     /   \
     *    /     .
     *   .       \
     *  / \       \
     * 1   \       .
     *      .     /
     *     / \   9
     *    3   5
     */
    private static Trie buildTestTrie() {
        Trie trie = new Trie();
        trie = trie.put(decode("0a"), new byte[] { 0x06 });
        trie = trie.put(decode("0a00"), new byte[] { 0x02 });
        trie = trie.put(decode("0a80"), new byte[] { 0x07 });
        trie = trie.put(decode("0a0000"), new byte[] { 0x01 });
        trie = trie.put(decode("0a0080"), new byte[] { 0x04 });
        trie = trie.put(decode("0a008000"), new byte[] { 0x03 });
        trie = trie.put(decode("0a008080"), new byte[] { 0x05 });
        trie = trie.put(decode("0a8080"), null);
        trie = trie.put(decode("0a808000"), new byte[] { 0x09 });

        trie = trie.put(decode("0a0080"), new byte[] { 0xA });
        return trie;
    }
}