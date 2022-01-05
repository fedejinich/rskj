package co.rsk.trie;

import org.junit.Test;
import org.junit.Assert;

import java.nio.charset.StandardCharsets;
import java.util.List;

import static org.bouncycastle.util.encoders.Hex.decode;

public class TrieUpdateRentTest {

    @Test
    public void updateRentTimestampBasicTest() {

    }

    //attempt to update timestamp for non-existent trie node should fail and return original trie
    @Test
    public void failedUpdateRentTimestampNonExistentNode() {
        Trie trie = new Trie();
        trie = trie.put("f", "42".getBytes());
        //try to update timestamp for node that does not exist
        Trie trie2 = trie.updateLastRentPaidTimestamp(str2slice("foo"), 20L);
        Assert.assertEquals(trie, trie2); //return original trie unchanged
    }

    //modifiedfrom TrieGetNodesTest : putAndGetKeyAndSubKeyValuesAndGetNodes()
    /**Check put followed by putWithRent and then put again (same node) 
     * Check that timestamp updates are propogated from child to parent, all the way till root 
    */
    @Test
    public void putAndGetKeyWithRent() {
        /*    The final trie for this test
        *         .
        *        / \
        *       f   bar (this is added last, creating a split, timestamp 50)
        *      /      
        *    foo       
        *    /
        *  food (timestamp 30)  
        */

        Trie trie = new Trie();
        // insert 2 nodes
        trie = trie.put("f", "42".getBytes());
        trie = trie.put("foo", "bar".getBytes());
        trie = trie.updateLastRentPaidTimestamp(str2slice("foo"), 20L);//add rent timestamp to leaf node
        trie = trie.put("foo", "Nobar".getBytes());  //update value
        
        List<Trie> nodes = trie.getNodes("foo");
        
        Assert.assertEquals(20L, nodes.get(0).getLastRentPaidTimestamp()); //check leaf node timestamp
        Assert.assertEquals(20L, nodes.get(1).getLastRentPaidTimestamp()); //check parent gets child's rentupdate
        Assert.assertArrayEquals("Nobar".getBytes(), nodes.get(0).getValue());

        trie = trie.put("food", "extendbranch".getBytes()); //extend branch
        trie = trie.updateLastRentPaidTimestamp(str2slice("food"), 30L); //add a timestamp to new leaf node
        
        //split the trie, creating a new branch
        trie = trie.put("bar", "splittrie".getBytes()); //this will split the trie
        trie = trie.updateLastRentPaidTimestamp(str2slice("bar"), 50L);

        nodes = trie.getNodes("food");
        
        Assert.assertEquals(30L, nodes.get(0).getLastRentPaidTimestamp());
        Assert.assertEquals(30L, nodes.get(1).getLastRentPaidTimestamp());
        Assert.assertEquals(30L, nodes.get(2).getLastRentPaidTimestamp());
        
        //should be different from above, because rent update from other branch is more recent
        Assert.assertEquals(50L, nodes.get(3).getLastRentPaidTimestamp()); 
        Assert.assertNull(nodes.get(3).getValue()); //this internal node has no value
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


    //convenience method since updateLastRentPaidTime does not accept string input
    private static TrieKeySlice str2slice(String key){
        TrieKeySlice keySlice = TrieKeySlice.fromKey(key.getBytes(StandardCharsets.UTF_8));
        return keySlice;
    }
}