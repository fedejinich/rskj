// Sanity check of the reproducer hints in spec/obligations.json against the real rskj classes.
// NOT a verification result: it only confirms that each hint shows the behaviour the spec
// reading describes. Run:  . verification/trie/env.sh
//   jshell --class-path "$(rskj_classpath)" -R-Dlogback.configurationFile=/dev/null \
//          verification/trie/spec/sanity/ReproHints.jsh
import co.rsk.trie.*;
import org.ethereum.datasource.HashMapDB;
import org.ethereum.crypto.Keccak256Helper;
import org.ethereum.util.ByteUtil;
import java.util.Arrays;

String hex(byte[] b) { return b == null ? "null" : ByteUtil.toHexString(b); }
byte[] h(String s) { return org.bouncycastle.util.encoders.Hex.decode(s); }
byte[] cat(byte[]... xs) { var o = new java.io.ByteArrayOutputStream(); for (var x : xs) o.writeBytes(x); return o.toByteArray(); }
byte[] rep(int n, int v) { byte[] b = new byte[n]; Arrays.fill(b, (byte) v); return b; }
void show(String id, Object o) { System.out.println(id + " => " + o); }
String tryParse(byte[] m) { try { return hex(Trie.fromMessage(m, null).toMessage()); } catch (Throwable e) { return "THROWS " + e.getClass().getSimpleName(); } }

// Everything runs inside run(): top-level jshell variables are displayed via toString(), which
// calls getHash() and would cache encodings before the checks run (this masks HASH-04).
void run() {

// NODE-05: root with value and a left embedded child
Trie t5 = new Trie().put(h("00"), h("01")).put(h("0000"), h("02"));
show("NODE-05 flags(root{00:01,0000:02})", hex(Arrays.copyOf(t5.toMessage(), 1)) + " full=" + hex(t5.toMessage()));

// HASH-02: empty trie
show("HASH-02 emptyHash", new Trie().getHash().toHexString() + " toMessage=" + hex(new Trie().toMessage()) + " keccak(toMessage)=" + hex(Keccak256Helper.keccak256(new Trie().toMessage())));

// NODE-02: version bits not checked
show("NODE-02 parse c001", tryParse(h("c001")));
show("NODE-02 parse 8001", tryParse(h("8001")));
show("NODE-02 parse 00", tryParse(h("00")));
show("NODE-02 parse 0101", tryParse(h("0101")));

// PATH-03: non-zero padding bits
show("PATH-03 parse 5000ff01", tryParse(h("5000ff01")));

// LSH-05: non-canonical lshared forms
show("LSH-05 parse 50ff050001 (escape for 5)", tryParse(h("50ff050001")));
show("LSH-05 parse 50fffd05000001 (non-minimal varint)", tryParse(h("50fffd05000001")));
show("LSH-05 parse 50ffff0500000001000000" + "0001 (9-byte varint 2^32+5)", tryParse(h("50ffff05000000010000000001")));
show("LSH-05 parse 50ff0001 (lshared 0 via escape)", tryParse(h("50ff0001")));

// VAL-06: inline value > 32 bytes accepted
show("VAL-06 parse 40||33x00", tryParse(cat(h("40"), rep(33, 0))));
Trie v6b = Trie.fromMessage(cat(h("60"), rep(32, 0xaa), h("000001")), null);
show("VAL-06 parse 60||32xaa||000001 valueLength", v6b.getValueLength() + " hasLongValue=" + v6b.hasLongValue());
Trie v6c = Trie.fromMessage(cat(h("60"), rep(32, 0xaa), h("000000")), null);
show("VAL-06 parse 60||32xaa||000000 isEmptyTrie", v6c.isEmptyTrie() + " toMessage=" + hex(v6c.toMessage()));

// EMB-02: embedded non-terminal node accepted
byte[] innerNonTerminal = cat(h("48"), rep(32, 0x11), h("00"));   // 34 bytes, left child by hash
byte[] parentEmb = cat(h("4a"), new byte[]{(byte) innerNonTerminal.length}, innerNonTerminal, h("00"));
show("EMB-02 parse parent embedding non-terminal", "in=" + hex(parentEmb) + " out=" + tryParse(parentEmb));

// SER-03: embedded flag without presence, embedded empty node
show("SER-03 parse 4201 (left-embedded bit, no presence)", tryParse(h("4201")));
show("SER-03 parse 4a01400001 (embedded empty node)", tryParse(h("4a01400001")));

// EMB-03 / SIZE-01: 43-byte embedded leaves, childrenSize on non-terminal
Trie t9 = new Trie().put(cat(h("00"), rep(7, 0)), rep(32, 0x01)).put(cat(h("80"), rep(7, 0)), rep(32, 0x02));
byte[] m9 = t9.toMessage();
show("EMB-03 root flags/len-byte", hex(Arrays.copyOf(m9, 2)) + " rootLen=" + m9.length + " leafLen=" + t9.getLeft().getNode().get().getMessageLength());
show("SIZE-01 root childrenSize", t9.getChildrenSize().value + " leaf childrenSize=" + t9.getLeft().getNode().get().getChildrenSize().value);

// OPS-09: deleteRecursive on a non-boundary prefix deletes nothing
Trie t11 = new Trie().put(h("0102"), h("aa"));
show("OPS-09 deleteRecursive(01).get(0102)", hex(t11.deleteRecursive(h("01")).get(h("0102"))));

// VARINT-03: non-minimal treeSize VarInt accepted (NODE-05 root with childrenSize 04 written as fd0400)
show("VARINT-03 parse 5a07000450060002fd040001", tryParse(h("5a07000450060002fd040001")));

// SIZE-03: treeSize is not validated by the parser (true value is 4)
show("SIZE-03 parse 5a070004500600020501 childrenSize", Trie.fromMessage(h("5a070004500600020501"), null).getChildrenSize().value);

// NODE-08: non-terminal node with a long value: treeSize is written before valueHash/valueLength
Trie t8 = new Trie().put(h("01"), rep(33, 0xab)).put(h("0101"), h("02"));
show("NODE-08 root{01:33xab,0101:02}", hex(t8.toMessage()) + " keccak(33xab)=" + hex(Keccak256Helper.keccak256(rep(33, 0xab))));

// HASH-04: hash depends on whether a hash-referenced embeddable child was loaded
HashMapDB db12 = new HashMapDB();
TrieStoreImpl s12 = new TrieStoreImpl(db12);
byte[] child12 = h("50060001");                                   // lshared 7, path 0000000, value 01 (terminal, 4 bytes)
db12.put(Keccak256Helper.keccak256(child12), child12);
byte[] parent12 = cat(h("48"), Keccak256Helper.keccak256(child12), h("04"));
String h1 = Trie.fromMessage(parent12, s12).getHash().toHexString();
Trie t12 = Trie.fromMessage(parent12, s12); byte[] got12 = t12.get(h("00"));
String h2 = t12.getHash().toHexString();
show("HASH-04 hash before/after child load", h1 + " / " + h2 + " equal=" + h1.equals(h2) + " get(00)=" + hex(got12) + " keccak(parent)=" + hex(Keccak256Helper.keccak256(parent12)));

// STORE-02: empty root stored under EMPTY_HASH
HashMapDB db13 = new HashMapDB();
TrieStoreImpl s13 = new TrieStoreImpl(db13);
s13.save(new Trie(s13));
show("STORE-02 db[emptyHash]", hex(db13.get(new Trie().getHash().getBytes())));

// STORE-07: MultiTrieStore.collect copies nothing
MultiTrieStore mts = new MultiTrieStore(0, 3, name -> new TrieStoreImpl(new HashMapDB()), e -> {});
Trie t14 = new Trie(mts).put(rep(40, 1), rep(40, 2)).put(rep(40, 3), rep(40, 4));
mts.save(t14);
byte[] root14 = t14.getHash().getBytes();
String after = "";
for (int i = 1; i <= 3; i++) { try { mts.collect(root14); after += " collect" + i + ":retrieve=" + mts.retrieve(root14).isPresent(); } catch (Throwable e) { after += " collect" + i + ":THROWS " + e; } }
show("STORE-07 MultiTrieStore", after);

// OPS-08: value longer than 2^24-1 bytes
try { new Trie().put(h("01"), new byte[0x1000000]); show("OPS-08", "no exception"); } catch (Throwable e) { show("OPS-08", "THROWS " + e.getClass().getSimpleName() + ": " + e.getMessage()); }

// OPS-05: empty value == delete
Trie t15 = new Trie().put(h("01"), h("aa")).put(h("02"), h("bb"));
show("OPS-05 put(k,[]) vs delete(k) hash equal", t15.put(h("01"), new byte[0]).getHash().equals(t15.delete(h("01")).getHash()));

// KEY-01/05: key lengths
var km = new org.ethereum.db.TrieKeyMapper();
var addr = new co.rsk.core.RskAddress("0x0000000000000000000000000000000000000001");
show("KEY account/code/storagePrefix/storage(slot0) lengths", km.getAccountKey(addr).length + "/" + km.getCodeKey(addr).length + "/" + km.getAccountStoragePrefixKey(addr).length + "/" + hex(km.getAccountStorageKey(addr, org.ethereum.vm.DataWord.ZERO)));
}
run();
/exit
