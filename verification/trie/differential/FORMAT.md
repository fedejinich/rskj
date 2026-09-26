# Differential case format

The same case files run on the real Java classes (`java/DiffRunner.java`) and on the executable Lean
model (`lake exe trie-diff`). Both runners must print byte-identical output; `run.sh` diffs them.

## Input (`cases/*.cases`)

Line based; blank lines and lines starting with `#` are ignored. Byte strings are lowercase hex, or
`-` for the empty byte array.

```
case <name>
put <key> <value>           trie = trie.put(key, value)        (value "-" = empty array)
delete <key>                trie = trie.delete(key)
save                        store.save(trie)
reload                      trie = store.retrieve(trie.getHash().getBytes()).get()   (only after save, non-empty trie)
decode <bytes>              Trie.fromMessage(bytes, store), re-encoded with toMessage()
keymap-account <addr20>     TrieKeyMapper.getAccountKey(new RskAddress(addr))
keymap-code <addr20>        TrieKeyMapper.getCodeKey(...)
keymap-storage <addr20> <slot32>   TrieKeyMapper.getAccountStorageKey(addr, DataWord.valueOf(slot))
end
```

Each case starts from `new Trie(store)` over a fresh `TrieStoreImpl(new HashMapDB())`.

## Output

One block per case, in input order:

```
case <name>
step <i> <root>                     after the i-th put/delete (1-based): hex of trie.getHash()
decode <bytes> <reencoded|error>    per decode op; "error" if fromMessage/toMessage throws
decode <bytes> orchid <path> <left> <right> <value>
                                    when bytes[0] == 0x02 (legacy format) and it parses: path as a
                                    0/1 string ("-" if empty), child hashes or "-", value or "null"
                                    (no re-encoding: that would fetch children from the store)
keymap <op> <args...> <key>         per keymap op
root <root>                         final trie.getHash()
msg <message>                       final trie.toMessage()
get <key> <value|null>              for every distinct key used by put/delete, in first-use order
end
```

Hashes are real Keccak-256 on both sides.
