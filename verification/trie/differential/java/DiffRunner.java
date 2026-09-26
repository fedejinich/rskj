import co.rsk.core.RskAddress;
import co.rsk.trie.NodeReference;
import co.rsk.trie.Trie;
import co.rsk.trie.TrieStoreImpl;
import org.ethereum.datasource.HashMapDB;
import org.ethereum.db.TrieKeyMapper;
import org.ethereum.vm.DataWord;

import java.io.BufferedOutputStream;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;

/** Runs differential case files (see ../FORMAT.md) on the real, unmodified rskj trie classes. */
public final class DiffRunner {
    private static final HexFormat HEX = HexFormat.of();

    private static byte[] bytes(String s) {
        return s.equals("-") ? new byte[0] : HEX.parseHex(s);
    }

    private static String hex(byte[] b) {
        if (b == null) {
            return "null";
        }
        return b.length == 0 ? "-" : HEX.formatHex(b);
    }

    private static String bits(byte[] expanded) {
        StringBuilder sb = new StringBuilder();
        for (byte b : expanded) {
            sb.append(b);
        }
        return sb.length() == 0 ? "-" : sb.toString();
    }

    private static String ref(NodeReference r) {
        return r.getHash().map(h -> hex(h.getBytes())).orElse("-");
    }

    // Orchid nodes are described field by field: re-encoding one with children would make
    // Trie.getChildrenSize() fetch the children from the store, and a miss calls System.exit(1).
    private static String decode(byte[] message, TrieStoreImpl store) {
        try {
            Trie t = Trie.fromMessage(message, store);
            if (message[0] == 2) {
                return "orchid " + bits(t.getSharedPath().expand()) + " " + ref(t.getLeft()) + " "
                        + ref(t.getRight()) + " " + hex(t.getValue());
            }
            return hex(t.toMessage());
        } catch (RuntimeException | StackOverflowError e) {
            System.err.println("decode " + hex(message) + ": " + e);
            return "error";
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader in = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        PrintStream out = new PrintStream(new BufferedOutputStream(System.out), false, StandardCharsets.UTF_8);
        TrieKeyMapper mapper = new TrieKeyMapper();
        TrieStoreImpl store = null;
        Trie trie = null;
        List<String> keys = new ArrayList<>();
        int step = 0;
        String line;
        while ((line = in.readLine()) != null) {
            line = line.strip();
            if (line.isEmpty() || line.startsWith("#")) {
                continue;
            }
            String[] f = line.split(" +");
            switch (f[0]) {
                case "case" -> {
                    store = new TrieStoreImpl(new HashMapDB());
                    trie = new Trie(store);
                    keys = new ArrayList<>();
                    step = 0;
                    out.println("case " + f[1]);
                }
                case "put", "delete" -> {
                    trie = f[0].equals("put") ? trie.put(bytes(f[1]), bytes(f[2])) : trie.delete(bytes(f[1]));
                    if (!keys.contains(f[1])) {
                        keys.add(f[1]);
                    }
                    out.println("step " + ++step + " " + hex(trie.getHash().getBytes()));
                }
                case "save" -> store.save(trie);
                case "reload" -> trie = store.retrieve(trie.getHash().getBytes()).orElseThrow();
                case "decode" -> out.println("decode " + f[1] + " " + decode(bytes(f[1]), store));
                case "keymap-account" -> out.println("keymap account " + f[1] + " "
                        + hex(mapper.getAccountKey(new RskAddress(bytes(f[1])))));
                case "keymap-code" -> out.println("keymap code " + f[1] + " "
                        + hex(mapper.getCodeKey(new RskAddress(bytes(f[1])))));
                case "keymap-storage" -> out.println("keymap storage " + f[1] + " " + f[2] + " "
                        + hex(mapper.getAccountStorageKey(new RskAddress(bytes(f[1])), DataWord.valueOf(bytes(f[2])))));
                case "end" -> {
                    out.println("root " + hex(trie.getHash().getBytes()));
                    out.println("msg " + hex(trie.toMessage()));
                    for (String k : keys) {
                        out.println("get " + k + " " + hex(trie.get(bytes(k))));
                    }
                    out.println("end");
                }
                default -> throw new IllegalArgumentException("unknown op: " + line);
            }
        }
        out.flush();
    }
}
