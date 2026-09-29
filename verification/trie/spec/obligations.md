# Trie obligations from the RSKIPs (Stage 1)

Generated from `obligations.json` by `render_md.py`; edit the JSON, not this file.

## Sources

- RSKIPs: read-only clone `/Users/void_rsk/.treehouse/firstmate-ff549e/6/firstmate/projects/rskips-fork` at `c578f4e932854830bb81f3de209eeeda6f7724b1`.
- rskj: `ecef55ddf2b79fe5cd84c824118117dd825744b2`; Java cited as `path:line` at that commit. In the tables below, paths are relative to `rskj-core/src/main/java/` (the JSON keeps full repo-relative paths), and every Java reading is a code reading, not a verification verdict.
- `co.rsk.bitcoinj.core.VarInt` from `bitcoinj-thin-0.14.4-rsk-18.jar` (on `rskj_classpath`), read with `javap -c`.
- `rskip-index.md` lists every RSKIP read and why it is in or out of scope.

## RSKIPs used

- **In scope:** RSKIP107 (node format, the core of Stage 1), RSKIP108 (key mapping), RSKIP24 (design goals, immutability), RSKIP16 (Unitrie layout, field selectors), RSKIP64 (epoch stores, only for `MultiTrieStore`). RSKIP240 is cited only for its node-version numbering and the 32-byte threshold; RSKIP242/244 only for the 44-byte embedding threshold; RSKIP112 is recorded as one informational obligation.
- **Out of scope:** gas, rent, parallel execution and code merkleization proposals (RSKIP109, 113, 144, 173, 239, 240's rent mechanics, 243, 244's gas); none changes the Stage 1 trie code at this commit. RSKIP126 has no file in the clone; its activation is still the evidence that the RSKIP107 hash is consensus.

## Applicability

- **RSKIP107:** Status Draft (IPs/RSKIP107.md:5; README.md:118). No ConsensusRule for 107: rskj always serializes nodes in this format. Its node hash is consensus for the state root from RSKIP126 (ConsensusRule.java:41; reference.conf:28 rskip126 = wasabi100; config/main.conf:8 wasabi100 = 1591000; testnet/regtest wasabi100 = 0; co/rsk/db/StateRootHandler.java:41-52) and for tx/receipt roots (co/rsk/core/bc/BlockHashesHelper.java:22-29,76-83; before RSKIP126 those use getHashOrchid). The RSKIPs clone has no IPs/RSKIP126.md.
- **RSKIP108:** Status Draft (IPs/RSKIP108.md:5; README.md:119). No ConsensusRule; TrieKeyMapper applies the mapping unconditionally in the current code.
- **RSKIP24:** Status Adopted (IPs/RSKIP24.md:5, :23) with 'Parts of this document has been deprecated' (IPs/RSKIP24.md:29). Only its design goals and immutability statement are used.
- **RSKIP64:** Status Draft (IPs/RSKIP64.md:5). Implemented by MultiTrieStore/GarbageCollector, used only when blockchain.gc.enabled (reference.conf:110-114, default false; co/rsk/RskContext.java:1605-1607).

## Conventions

- **java.reading:** Code reading by the spec helper, not a verification verdict: conforms / diverges / unclear.
- **reachable trie:** A trie obtained from new Trie() or new Trie(store) by put/delete/deleteRecursive (all nodes in memory).
- **canonical-parse reading:** The reading that Trie.fromMessage should accept only encodings that toMessage can produce (fromMessage(m).toMessage() == m). No RSKIP states it; obligations using it are kind=ambiguity.
- **sanity:** spec/sanity/ReproHints.jsh runs every reproducer hint marked 'Sanity run' against the real compiled classes; output in spec/sanity/ReproHints.out.
- **kind:** `requirement` = the RSKIP states it (quoted); `derived` = implied by the quoted text; `ambiguity` = the text is contradictory, underspecified or silent, and the statement records the reading Java implements.

80 Stage 1 obligations and 3 Stage 2 obligations. Java readings across all of them: 56 conforms, 18 diverges, 9 unclear.

## KEY: Key mapping

| ID | Kind | Statement | Citation | Java reading |
| --- | --- | --- | --- | --- |
| TRIE-KEY-01 | requirement | **Account key layout.** For every 20-byte address a, TrieKeyMapper.getAccountKey(a) == 0x00 ++ keccak256(a)[0..10) ++ a (31 bytes). | `IPs/RSKIP108.md:61; 32` | **conforms**: DOMAIN_PREFIX 0x00, SECURE_KEY_SIZE 10, then the raw address. (`org/ethereum/db/TrieKeyMapper.java:38`, `org/ethereum/db/TrieKeyMapper.java:42`, `org/ethereum/db/TrieKeyMapper.java:48-59`, `org/ethereum/db/TrieKeyMapper.java:77-79`, `org/ethereum/db/TrieKeyMapper.java:89-92`) |
| TRIE-KEY-02 | ambiguity | **Hash-prefix slice notation [0:9] / [0..9] vs 80 bits.** The hash prefix in account and storage keys is exactly 10 bytes: TrieKeyMapper.secureKeyPrefix(x).length == 10 and == keccak256(x)[0..10). | `IPs/RSKIP108.md:61-64; 32` | **conforms**: Readings: (a) [0:9] half-open = 9 bytes (72 bits); (b) inclusive 0..9 = 10 bytes (80 bits). The prose says 80 bits and 'account trie keys consuming only 30 bytes' (10+20), so (b); Java implements (b). (`org/ethereum/db/TrieKeyMapper.java:38`, `org/ethereum/db/TrieKeyMapper.java:77-79`) |
| TRIE-KEY-03 | requirement | **Code key.** getCodeKey(a) == getAccountKey(a) ++ 0x80 (32 bytes). | `IPs/RSKIP108.md:62; RSKIP16.md:50-53` | **conforms** (`org/ethereum/db/TrieKeyMapper.java:44`, `org/ethereum/db/TrieKeyMapper.java:61-63`) |
| TRIE-KEY-04 | requirement | **Storage-root (placeholder) key.** getAccountStoragePrefixKey(a) == getAccountKey(a) ++ 0x00 (32 bytes). | `IPs/RSKIP108.md:63` | **conforms** (`org/ethereum/db/TrieKeyMapper.java:43`, `org/ethereum/db/TrieKeyMapper.java:65-67`) |
| TRIE-KEY-05 | requirement | **Storage-root placeholder value is 0x00.** When an account's storage subtree is created, the value stored at getAccountStoragePrefixKey(a) is the single byte 0x00. | `IPs/RSKIP108.md:63` | **diverges**: MutableRepository writes ONE_BYTE_ARRAY = {0x01} at the storage prefix key (and the comment at :394 says 'The value should be ONE_BYTE_ARRAY'). (`org/ethereum/db/MutableRepository.java:56`, `org/ethereum/db/MutableRepository.java:107-108`, `org/ethereum/db/MutableRepository.java:392-395`) |
| TRIE-KEY-06 | requirement | **Storage cell key layout.** getAccountStorageKey(a, s) == getAccountStoragePrefixKey(a) ++ keccak256(H)[0..10) ++ trim(s), where trim is TRIE-KEY-08 and H is the hash input fixed by TRIE-KEY-07 (Java: the 32-byte word s). | `IPs/RSKIP108.md:64` | **conforms**: Conforms under the 32-byte-input reading of TRIE-KEY-07. (`org/ethereum/db/TrieKeyMapper.java:69-75`, `org/ethereum/db/TrieKeyMapper.java:77-79`) |
| TRIE-KEY-07 | ambiguity | **Hash input of the storage-address prefix.** The 10-byte storage prefix is keccak256 of the full 32-byte storage address (not of trimmed_storage_address). | `IPs/RSKIP108.md:64; 34` | **unclear**: Readings: SHA3 over (a) the 256-bit address as a 32-byte word, or (b) the trimmed address. Java uses (a); its own comment at :70 asks 'should we hash the full subkey or the stripped one?'. (`org/ethereum/db/TrieKeyMapper.java:69-73`) |
| TRIE-KEY-08 | requirement | **trimmed_storage_address.** trim(s) = s without leading zero bytes if s != 0, and trim(0) = [0x00]; ByteUtil.stripLeadingZeroes(s) implements it for 32-byte s. | `IPs/RSKIP108.md:66` | **conforms**: stripLeadingZeroes returns ZERO_BYTE_ARRAY {0x00} for an all-zero input. (`org/ethereum/util/ByteUtil.java:41`, `org/ethereum/util/ByteUtil.java:406-418`, `org/ethereum/db/TrieKeyMapper.java:73`) |
| TRIE-KEY-09 | derived | **Key mapping is injective and kinds are disjoint.** Distinct (kind, address, slot) triples map to distinct keys: getAccountKey is injective; account keys (31 B), code keys (32 B, last byte 0x80), storage-prefix keys (32 B, last byte 0x00) and storage keys (43..74 B) never coincide; getAccountStorageKey(a,s) == getAccountStorageKey(a',s') implies a == a' and s == s'. | `IPs/RSKIP108.md:32; 59-64` | **conforms**: Address bytes are embedded verbatim; trim is injective on 32-byte words. (`org/ethereum/db/TrieKeyMapper.java:48-92`) |
| TRIE-KEY-10 | requirement | **RSKIP112 value type specifiers.** Every non-zero value stored in the Unitrie starts with one ASCII type byte: 'A' account, 'S' storage cell, 'R' storage root, 'D' code. | `IPs/RSKIP112.md:35-42` | **diverges**: rskj stores raw values (account RLP, code bytes, stripped storage words, 0x01 placeholder) with no type byte. (`org/ethereum/db/MutableRepository.java:56`, `org/ethereum/db/MutableRepository.java:107-108`, `org/ethereum/db/MutableRepository.java:252-255`) |

## PATH: Bit-path encoding

| ID | Kind | Statement | Citation | Java reading |
| --- | --- | --- | --- | --- |
| TRIE-PATH-01 | ambiguity | **Key bytes to bit path: MSB first.** TrieKeySlice.fromKey(k) is the bit string of length 8*\|k\| where bit 8i+j is bit (7-j) of k[i] (most significant bit first). | `IPs/RSKIP107.md:39; RSKIP16.md:58` | **unclear**: RSKIPs count the shared prefix in bits but never fix the bit order inside a key byte. Java: MSB first (PathEncoder comments ':48 First bit is MOST SIGNIFICANT'). TrieKeyMapper.java:43-44 relies on it ('This makes the MSB 0/1 be branching'). (`co/rsk/trie/TrieKeySlice.java:109-115`, `co/rsk/trie/PathEncoder.java:72-88`) |
| TRIE-PATH-02 | ambiguity | **Implicit branch bit; 0 = left, 1 = right.** A node's full key is parentKey ++ [b] ++ sharedPath where b is 0 for the left child and 1 for the right child; b is not stored in the child's shared path. find/put descend with getNodeReference(b), b = key.get(sharedPath.length()). | `IPs/RSKIP107.md:36-38` | **unclear**: No RSKIP states that the branch bit is implicit or which bit value selects left. Java: bit 0 -> left, bit 1 -> right, bit implicit. (`co/rsk/trie/Trie.java:669`, `co/rsk/trie/Trie.java:749-751`, `co/rsk/trie/Trie.java:875-884`, `co/rsk/trie/Trie.java:612`, `co/rsk/trie/TrieKeySlice.java:86-97`) |
| TRIE-PATH-03 | ambiguity | **encodedSharedPath packing.** PathEncoder.encode(p) has length ceil(\|p\|/8) (calculateEncodedLength), packs bits MSB first, sets padding bits to 0, and PathEncoder.decode(encode(p), \|p\|) == p. | `IPs/RSKIP107.md:61-63` | **conforms**: The RSKIP gives no packing; conforms to the MSB-first, zero-padded reading. (`co/rsk/trie/PathEncoder.java:49-70`, `co/rsk/trie/PathEncoder.java:75-88`, `co/rsk/trie/PathEncoder.java:90-92`, `co/rsk/trie/TrieKeySlice.java:45-48`, `co/rsk/trie/TrieKeySlice.java:117-122`) |
| TRIE-PATH-04 | ambiguity | **Parser ignores non-zero padding bits.** Canonical-parse reading: Trie.fromMessage rejects an encodedSharedPath whose padding bits (beyond lshared) are not zero. | `IPs/RSKIP107.md:61-63` | **diverges**: decodeBinaryPath reads only the first lshared bits; padding is ignored, so two byte strings parse to the same node and getHash() != keccak256(message). (`co/rsk/trie/PathEncoder.java:75-88`, `co/rsk/trie/SharedPathSerializer.java:137-148`, `co/rsk/trie/Trie.java:269`) |
| TRIE-PATH-05 | derived | **Key-slice operations.** TrieKeySlice.commonPath(a,b) returns the longest common prefix of a and b; slice(i,j) returns bits i..j-1 (throws on bad bounds); a.rebuildSharedPath(b, c) returns a ++ [b] ++ c. | `IPs/RSKIP107.md:39` | **conforms** (`co/rsk/trie/TrieKeySlice.java:37-43`, `co/rsk/trie/TrieKeySlice.java:50-81`, `co/rsk/trie/TrieKeySlice.java:86-97`) |

## LSH: Shared-prefix length compression

| ID | Kind | Statement | Citation | Java reading |
| --- | --- | --- | --- | --- |
| TRIE-LSH-01 | requirement | **lshared 1..32 is one byte lshared-1.** For 1 <= l <= 32, SharedPathSerializer.serializeBytes writes the single byte l-1, and getPathBitsLength maps a first byte 0..31 to l = byte+1. | `IPs/RSKIP107.md:97-99` | **conforms** (`co/rsk/trie/SharedPathSerializer.java:66-68`, `co/rsk/trie/SharedPathSerializer.java:125-127`) |
| TRIE-LSH-02 | requirement | **lshared 160..382 is one byte lshared-128.** For 160 <= l <= 382, serializeBytes writes the single byte l-128 (32..254), and getPathBitsLength maps a first byte 32..254 to l = byte+128. | `IPs/RSKIP107.md:100` | **conforms** (`co/rsk/trie/SharedPathSerializer.java:69-71`, `co/rsk/trie/SharedPathSerializer.java:128-130`) |
| TRIE-LSH-03 | ambiguity | **Escape 255 + Bitcoin VarInt for other lengths.** For l in 33..159 or l >= 383, serializeBytes writes 0xFF followed by VarInt(l).encode() (the VarInt carries l itself); calculateVarIntSize(l) == 1 + VarInt.sizeOf(l). | `IPs/RSKIP107.md:101; 103` | **conforms**: RSKIP leaves open what the VarInt encodes (l, or l minus an offset) and says '2 additional bytes' while VarInt takes 1..9. Java: VarInt(l); l in 33..159 costs 2 bytes in total (marker + 1). (`co/rsk/trie/SharedPathSerializer.java:72-75`, `co/rsk/trie/SharedPathSerializer.java:104-114`, `co/rsk/trie/SharedPathSerializer.java:131-133`) |
| TRIE-LSH-04 | requirement | **sharedPrefixPresent flag and presence of prefix fields.** In toMessage, flag bit 4 (0x10) is set iff sharedPath.length() > 0, and lsharedCompressed ++ encodedSharedPath are written iff it is set. | `IPs/RSKIP107.md:55; 58-63` | **conforms** (`co/rsk/trie/Trie.java:699-701`, `co/rsk/trie/Trie.java:721`, `co/rsk/trie/SharedPathSerializer.java:48-63`) |
| TRIE-LSH-05 | derived | **lshared round trip.** For every path p with \|p\| >= 1, SharedPathSerializer.deserialize(buffer after serializeInto(p), true) == p and consumes exactly getSerializedLength(p) bytes. | `IPs/RSKIP107.md:97-101` | **conforms** (`co/rsk/trie/SharedPathSerializer.java:56-77`, `co/rsk/trie/SharedPathSerializer.java:120-148`, `co/rsk/trie/SharedPathSerializer.java:189-195`) |
| TRIE-LSH-06 | ambiguity | **Parser accepts non-canonical lshared encodings.** Canonical-parse reading: getPathBitsLength accepts the escape form only for lengths outside 1..32 and 160..382, only minimal VarInts, only values that fit in an int, and never lshared = 0 with sharedPrefixPresent set. | `IPs/RSKIP107.md:97-101` | **diverges**: All four non-canonical forms are accepted; the 9-byte VarInt is truncated by the (int) cast at :132. (`co/rsk/trie/SharedPathSerializer.java:120-135`, `co/rsk/trie/SharedPathSerializer.java:167-183`, `co/rsk/trie/Trie.java:263`, `co/rsk/trie/Trie.java:269`) |

## VARINT: VarInt

| ID | Kind | Statement | Citation | Java reading |
| --- | --- | --- | --- | --- |
| TRIE-VARINT-01 | requirement | **VarInt encoding table.** For 0 <= v < 2^64 (as unsigned), VarInt(v).encode() is: [v] if v < 0xFD; 0xFD ++ uint16LE(v) if v <= 0xFFFF; 0xFE ++ uint32LE(v) if v <= 0xFFFFFFFF; else 0xFF ++ uint64LE(v). | `IPs/RSKIP107.md:105-114` | **conforms**: bitcoinj sizeOf/encode follow the table; negative Java longs are treated as 9-byte values. (co.rsk.bitcoinj.core.VarInt (bitcoinj-thin-0.14.4-rsk-18.jar, decompiled with javap -c: VarInt(long), VarInt(byte[],int), sizeOf, encode), `co/rsk/trie/Trie.java:728`, `co/rsk/trie/SharedPathSerializer.java:74`) |
| TRIE-VARINT-02 | derived | **VarInt round trip and exact consumption.** For every v, reading encode(v) with Trie.readVarInt / SharedPathSerializer.readVarInt returns v and advances the buffer by exactly encode(v).length bytes. | `IPs/RSKIP107.md:105-114` | **conforms** (`co/rsk/trie/Trie.java:1149-1165`, `co/rsk/trie/SharedPathSerializer.java:167-183`, co.rsk.bitcoinj.core.VarInt (bitcoinj-thin-0.14.4-rsk-18.jar, decompiled with javap -c: VarInt(long), VarInt(byte[],int), sizeOf, encode)) |
| TRIE-VARINT-03 | ambiguity | **Non-minimal VarInt accepted.** Canonical-parse reading: the node parser rejects a VarInt (treeSize or escaped lshared) that is longer than VarInt.sizeOf(value). | `IPs/RSKIP107.md:109-114` | **diverges**: bitcoinj VarInt(byte[],int) has no minimality check. (co.rsk.bitcoinj.core.VarInt (bitcoinj-thin-0.14.4-rsk-18.jar, decompiled with javap -c: VarInt(long), VarInt(byte[],int), sizeOf, encode), `co/rsk/trie/Trie.java:1149-1165`, `co/rsk/trie/SharedPathSerializer.java:167-183`) |

## NODE: Node format

| ID | Kind | Statement | Citation | Java reading |
| --- | --- | --- | --- | --- |
| TRIE-NODE-01 | requirement | **Version bits 6-7 = 01.** For every node, toMessage()[0] & 0xC0 == 0x40. | `IPs/RSKIP107.md:52-53` | **conforms** (`co/rsk/trie/Trie.java:693-694`) |
| TRIE-NODE-02 | ambiguity | **Parser dispatch on version.** fromMessage parses a message as RSKIP107 only if flags bits 6-7 == 01 and rejects versions 10 and 11 (rent format is not implemented); version-00 input other than an Orchid node (first byte 0x02) is rejected. | `IPs/RSKIP240.md:53; RSKIP107.md:53` | **diverges**: Java selects Orchid iff message[0] == 0x02 and otherwise parses as RSKIP107 without reading the version bits ('if we reached here, we don't need to check the version flag'). (`co/rsk/trie/Trie.java:163-175`, `co/rsk/trie/Trie.java:259-261`) |
| TRIE-NODE-03 | requirement | **hasLongValue flag is bit 5.** For every node n, (n.toMessage()[0] & 0x20 != 0) == n.hasLongValue(); the parser reads bit 5 as hasLongVal. | `IPs/RSKIP107.md:54` | **conforms** (`co/rsk/trie/Trie.java:695-697`, `co/rsk/trie/Trie.java:262`) |
| TRIE-NODE-04 | ambiguity | **Child presence/embedding flag bits.** The four low flag bits follow the RSKIP: presence of left/right and embedding of left/right at the bit positions the text assigns. | `IPs/RSKIP107.md:56-57; 64-75` | **diverges**: The text swaps names and descriptions (nodePresent is described as 'embedded', nodeIsEmbedded as 'presence'); the conditional layout at :64-75 uses nodePresent as presence. Reading A (by name): present L=bit2 R=bit3, embedded L=bit0 R=bit1. Reading B (by description): embedded L=bit2 R=bit3, present L=bit0 R=bit1. Java: present L=bit3 (0x08) R=bit2 (0x04), embedded L=bit1 (0x02) R=bit0 (0x01); this matches neither reading (it is reading A with left/right exchanged). (`co/rsk/trie/Trie.java:703-717`, `co/rsk/trie/Trie.java:264-267`) |
| TRIE-NODE-05 | requirement | **Field order up to child references.** toMessage() = flags ++ [lsharedCompressed ++ encodedSharedPath] ++ [left reference] ++ [right reference] ++ rest, and fromMessageRskip107 reads the fields in the same order. | `IPs/RSKIP107.md:50-75` | **conforms** (`co/rsk/trie/Trie.java:719-725`, `co/rsk/trie/Trie.java:259-307`) |
| TRIE-NODE-06 | requirement | **Child reference encoding.** A present, non-embedded child is written as its 32-byte node hash; an embedded child as uint8 length ++ the child's toMessage(). | `IPs/RSKIP107.md:64-75` | **conforms**: Size limit and terminal-only rule are TRIE-EMB-01/03. (`co/rsk/trie/NodeReference.java:156-180`, `co/rsk/trie/Trie.java:273-307`) |
| TRIE-NODE-07 | ambiguity | **treeSize presence condition.** Literal reading: treeSize is written iff the node has no children. Java: childrenSize VarInt is written iff the node has at least one child. | `IPs/RSKIP107.md:80-82` | **diverges**: Java does the opposite of the literal text; the literal condition makes treeSize ('the size of the tree') meaningless for leaves, so the text is probably negated by mistake. (`co/rsk/trie/Trie.java:689`, `co/rsk/trie/Trie.java:727-729`, `co/rsk/trie/Trie.java:309-312`) |
| TRIE-NODE-08 | ambiguity | **treeSize position relative to long-value fields.** Literal order: ... right reference, valueHash, valueLength, treeSize, value. Java order: ... right reference, childrenSize, valueHash, valueLength \| value. | `IPs/RSKIP107.md:76-82` | **diverges**: For a node with children and a long value, Java writes childrenSize before valueHash; the RSKIP lists treeSize after valueLength. (`co/rsk/trie/Trie.java:727-736`, `co/rsk/trie/Trie.java:309-338`) |
| TRIE-NODE-09 | requirement | **Inline value fills the rest of the buffer.** If !hasLongValue, toMessage ends with exactly the value bytes (none if there is no value), and the parser takes all remaining bytes as the value (remaining 0 -> no value). | `IPs/RSKIP107.md:84-85` | **conforms** (`co/rsk/trie/Trie.java:734-736`, `co/rsk/trie/Trie.java:326-338`) |
| TRIE-NODE-10 | derived | **No trailing bytes after long-value fields.** fromMessageRskip107 throws IllegalArgumentException if bytes remain after valueLength of a long-value node. | `IPs/RSKIP107.md:76-78` | **conforms** (`co/rsk/trie/Trie.java:340-342`) |

## EMB: Embedded nodes

| ID | Kind | Statement | Citation | Java reading |
| --- | --- | --- | --- | --- |
| TRIE-EMB-01 | requirement | **Embedded nodes are terminal (writer).** For every node n, if toMessage() marks a child as embedded then that child isTerminal(). | `IPs/RSKIP107.md:118-120` | **conforms** (`co/rsk/trie/Trie.java:587-589`, `co/rsk/trie/NodeReference.java:141-148`) |
| TRIE-EMB-02 | ambiguity | **Parser accepts non-terminal embedded nodes.** Canonical-parse reading: fromMessage rejects a message whose embedded child has a child. | `IPs/RSKIP107.md:118-120` | **diverges**: Embedded bytes are parsed recursively with no terminal check (and recursion depth is bounded only by the uint8 sizes). (`co/rsk/trie/Trie.java:273-282`, `co/rsk/trie/Trie.java:291-300`) |
| TRIE-EMB-03 | ambiguity | **Embedding size limit: 40 vs 44 bytes.** RSKIP107 reading: an embedded child encoding is at most 40 bytes. Java embeds a terminal child iff getMessageLength() <= 44. | `IPs/RSKIP107.md:68-69; 74-75; RSKIP242.md:27; RSKIP244.md:33` | **diverges**: Diverges from RSKIP107 (40); agrees with the 44 stated in RSKIP242/244 (Draft). (`co/rsk/trie/Trie.java:68`, `co/rsk/trie/Trie.java:587-589`) |
| TRIE-EMB-04 | ambiguity | **Embedding is determined by the child's content.** For every node of a trie built from new Trie() by put/delete, a child is serialized embedded iff it is terminal and its getMessageLength() <= 44 (a function of the child alone). | `IPs/RSKIP107.md:57; 64-75` | **conforms**: RSKIP107 only says a flag 'indicates' embedding and never makes it mandatory. Java also requires the child object to be loaded (NodeReference.isEmbeddable returns false when lazyNode == null), which holds for in-memory tries but not for parsed ones; see TRIE-HASH-04. (`co/rsk/trie/NodeReference.java:141-148`, `co/rsk/trie/NodeReference.java:156-180`, `co/rsk/trie/Trie.java:587-589`) |
| TRIE-EMB-05 | requirement | **Embedded size byte is the exact length.** An embedded child is written as Uint8(len(child.toMessage())) ++ child.toMessage(), and the parser consumes exactly that many bytes for the child. | `IPs/RSKIP107.md:68-69; 74-75` | **conforms** (`co/rsk/trie/NodeReference.java:170-173`, `co/rsk/trie/Trie.java:274-282`, `co/rsk/trie/Trie.java:292-300`, `co/rsk/core/types/ints/Uint8.java:29-35`) |

## VAL: Long values

| ID | Kind | Statement | Citation | Java reading |
| --- | --- | --- | --- | --- |
| TRIE-VAL-01 | requirement | **Long value iff length > 32.** n.hasLongValue() == (n.getValueLength() > 32). | `IPs/RSKIP107.md:54; RSKIP240.md:85` | **conforms** (`co/rsk/trie/Trie.java:967-969`) |
| TRIE-VAL-02 | requirement | **Long-value fields.** If hasLongValue, toMessage contains valueHash (32 bytes) followed by valueLength as uint24, and no inline value bytes. | `IPs/RSKIP107.md:76-78` | **conforms** (`co/rsk/trie/Trie.java:731-733`, `co/rsk/trie/Trie.java:318-325`) |
| TRIE-VAL-03 | ambiguity | **valueHash is Keccak-256 of the value.** For every node with a value, getValueHash() == keccak256(getValue()). | `IPs/RSKIP107.md:77` | **conforms**: 'Hash digest' is not named; Java uses Keccak-256 (RSK's SHA3). (`co/rsk/trie/Trie.java:975-983`, `co/rsk/trie/Trie.java:331`) |
| TRIE-VAL-04 | ambiguity | **valueLength byte order.** valueLength is encoded big-endian: Uint24(n).encode() == [n>>16, n>>8, n] (low bytes). | `IPs/RSKIP107.md:78; 107` | **unclear**: If 'Longer numbers are encoded in little endian' (said in the VarInt paragraph) applies to uint24 fields, Java diverges; if it only concerns VarInt, the RSKIP is silent and Java chose big-endian. (`co/rsk/core/types/ints/Uint24.java:38-44`, `co/rsk/core/types/ints/Uint24.java:79-84`) |
| TRIE-VAL-05 | ambiguity | **Parser accepts non-canonical value encodings.** Canonical-parse reading: fromMessage rejects an inline value longer than 32 bytes and a long-value encoding with valueLength <= 32. | `IPs/RSKIP107.md:54; 76-85` | **diverges**: Both are accepted; the node then re-serializes in the other form. (`co/rsk/trie/Trie.java:318-338`) |
| TRIE-VAL-06 | derived | **Lazily retrieved long value matches valueHash.** For a node parsed from a store, getValue() returns v with keccak256(v) == getValueHash() and \|v\| == getValueLength(), or throws. | `IPs/RSKIP107.md:77-78` | **diverges**: Only the length is checked after retrieval; a store entry of the right length but wrong content is returned silently. Holds when the store is content-addressed (TRIE-STORE-04). (`co/rsk/trie/Trie.java:985-992`, `co/rsk/trie/Trie.java:1013-1037`) |
| TRIE-VAL-07 | derived | **Values are shorter than 2^24 bytes.** put(k, v) with \|v\| > 0xFFFFFF throws IllegalArgumentException; every stored value has length <= 0xFFFFFF. | `IPs/RSKIP107.md:78` | **conforms** (`co/rsk/core/types/ints/Uint24.java:22`, `co/rsk/core/types/ints/Uint24.java:30-35`, `co/rsk/trie/Trie.java:823-829`) |

## OPS: put / get / delete

| ID | Kind | Statement | Citation | Java reading |
| --- | --- | --- | --- | --- |
| TRIE-OPS-01 | derived | **Empty trie has no keys.** new Trie().get(k) == null for every key k. | `IPs/RSKIP24.md:50` | **conforms** (`co/rsk/trie/Trie.java:124-130`, `co/rsk/trie/Trie.java:405-416`, `co/rsk/trie/Trie.java:650-675`) |
| TRIE-OPS-02 | derived | **get after put.** For every reachable trie t, key k and value v with 1 <= \|v\| <= 0xFFFFFF: t.put(k, v).get(k) equals v (byte-wise). | `IPs/RSKIP24.md:50` | **conforms** (`co/rsk/trie/Trie.java:438-443`, `co/rsk/trie/Trie.java:770-778`, `co/rsk/trie/Trie.java:831-917`, `co/rsk/trie/Trie.java:919-940`, `co/rsk/trie/Trie.java:650-675`) |
| TRIE-OPS-03 | derived | **put does not affect other keys.** For reachable t and k' != k: t.put(k, v).get(k') equals t.get(k'). | `IPs/RSKIP24.md:50` | **conforms** (`co/rsk/trie/Trie.java:831-917`, `co/rsk/trie/Trie.java:919-940`) |
| TRIE-OPS-04 | derived | **get after delete.** For reachable t: t.delete(k).get(k) == null. | `IPs/RSKIP24.md:50` | **conforms** (`co/rsk/trie/Trie.java:470-472`, `co/rsk/trie/Trie.java:770-821`, `co/rsk/trie/Trie.java:831-869`) |
| TRIE-OPS-05 | derived | **delete does not affect other keys.** For reachable t and k' != k: t.delete(k).get(k') equals t.get(k'), including after node coalescing. | `IPs/RSKIP24.md:50` | **conforms** (`co/rsk/trie/Trie.java:770-821`, `co/rsk/trie/Trie.java:831-917`) |
| TRIE-OPS-06 | derived | **Empty value is delete.** For reachable t: t.put(k, new byte[0]) and t.put(k, null) are equal to t.delete(k) (same getHash() and same get results). | `IPs/RSKIP107.md:84-85` | **conforms**: Derived: an inline value that 'extends up to the bounds of the node buffer' cannot distinguish an empty value from no value, so storing [] must mean absence. (`co/rsk/trie/Trie.java:770-776`, `co/rsk/trie/Trie.java:470-472`) |
| TRIE-OPS-07 | derived | **A key and its extensions coexist.** For reachable t, keys k and k ++ s (\|s\| >= 1) with values v1, v2: t.put(k, v1).put(k ++ s, v2) gives get(k) == v1 and get(k ++ s) == v2, in either insertion order. | `IPs/RSKIP108.md:61-64` | **conforms**: Values live in internal nodes. (`co/rsk/trie/Trie.java:842-869`, `co/rsk/trie/Trie.java:919-940`) |
| TRIE-OPS-08 | requirement | **Tries are immutable.** After t2 = t.put(k, v) (or delete/deleteRecursive), t's get results and getHash() are unchanged; mutating the array passed to put or returned by get does not change any trie. | `IPs/RSKIP24.md:74` | **conforms**: New nodes are built on every change; value arrays are cloned on input and output. (`co/rsk/trie/Trie.java:859-872`, `co/rsk/trie/Trie.java:916`, `co/rsk/trie/Trie.java:985-992`, `co/rsk/trie/Trie.java:1075-1077`) |
| TRIE-OPS-09 | derived | **deleteRecursive removes a subtree.** If a node exists exactly at key k in reachable t, then t.deleteRecursive(k).get(k ++ s) == null for all s, and get(k') is unchanged for every k' that does not start with k. | `IPs/RSKIP240.md:153; RSKIP16.md:50` | **conforms**: Conforms under the precondition. Without it Java deletes nothing: if k ends inside a node's shared path, internalPut returns the node unchanged (:833-837). (`co/rsk/trie/Trie.java:474-480`, `co/rsk/trie/Trie.java:851-853`, `co/rsk/trie/Trie.java:831-840`) |

## CMP: Compression and canonical shape

| ID | Kind | Statement | Citation | Java reading |
| --- | --- | --- | --- | --- |
| TRIE-CMP-01 | derived | **Canonical shape.** In every reachable trie, each non-root node has a value or two children, and the root is the empty node, has a value, or has two children; no reachable node except the empty root has zero-length value and no children. | `IPs/RSKIP24.md:58; RSKIP107.md:39,58-63` | **conforms**: split always adds the second child or the value; delete coalesces a valueless single-child node with its child. (`co/rsk/trie/Trie.java:770-821`, `co/rsk/trie/Trie.java:831-917`, `co/rsk/trie/Trie.java:919-940`, `co/rsk/trie/NodeReference.java:44-55`) |
| TRIE-CMP-02 | derived | **Shape determined by the key/value map.** Two reachable tries with the same key -> value map are structurally equal (same shared paths, values and children at every node), whatever put/delete sequences produced them. | `IPs/RSKIP24.md:58` | **conforms** (`co/rsk/trie/Trie.java:770-940`) |
| TRIE-CMP-03 | derived | **Root hash independent of history.** Two reachable tries with the same key -> value map have equal getHash() and equal root toMessage(). | `IPs/RSKIP24.md:58` | **conforms**: Needs TRIE-CMP-02, TRIE-EMB-04 and TRIE-SIZE-02 (childrenSize is serialized, so incremental size bookkeeping must not depend on history). (`co/rsk/trie/Trie.java:362-376`, `co/rsk/trie/Trie.java:677-739`, `co/rsk/trie/Trie.java:891-916`) |

## HASH: Node and root hash

| ID | Kind | Statement | Citation | Java reading |
| --- | --- | --- | --- | --- |
| TRIE-HASH-01 | ambiguity | **Node hash is Keccak-256 of the RSKIP107 encoding.** For every non-empty node n, n.getHash() == keccak256(n.toMessage()). | `IPs/RSKIP107.md:26; 66` | **conforms**: Neither the hash function nor its preimage is specified; Java hashes toMessage() with Keccak-256. (`co/rsk/trie/Trie.java:362-376`) |
| TRIE-HASH-02 | ambiguity | **Empty-trie hash.** new Trie().getHash() == keccak256(RLP.encodeElement([])) == keccak256(0x80) = 56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421, whereas new Trie().toMessage() == 0x40 and keccak256(0x40) = e724d40619441ced66a271e59627b7bcd39c77447a4315561b4d21e7b7c9321c. | `IPs/RSKIP107.md:50-85` | **unclear**: No RSKIP defines the empty root. Java special-cases it (Ethereum's empty-trie root) instead of hashing the encoding, so TRIE-HASH-01 excludes the empty node. (`co/rsk/trie/Trie.java:75`, `co/rsk/trie/Trie.java:367-369`, `co/rsk/trie/Trie.java:1088-1090`) |
| TRIE-HASH-03 | derived | **Root hash binds the map.** Assuming keccak256 is injective: for reachable t1, t2, t1.getHash() == t2.getHash() implies t1 and t2 have the same key -> value map. | `IPs/RSKIP24.md:54` | **conforms**: Follows from TRIE-SER-02 (encoding injective on canonical nodes) and child hashes or full encodings being included in the parent. (`co/rsk/trie/Trie.java:362-376`, `co/rsk/trie/Trie.java:677-739`, `co/rsk/trie/NodeReference.java:168-180`) |
| TRIE-HASH-04 | derived | **Hash independent of lazy loading.** For any node t parsed from a store, t.getHash() does not depend on which children were loaded (via get/find/getNode) before getHash() is first called. | `IPs/RSKIP24.md:76; 54` | **diverges**: NodeReference.isEmbeddable depends on whether the child object is cached. For stores written by TrieStoreImpl.save this cannot trigger (an embeddable child is never stored by hash); it does for store content that references an embeddable terminal child by hash. (`co/rsk/trie/NodeReference.java:141-148`, `co/rsk/trie/NodeReference.java:103-126`, `co/rsk/trie/Trie.java:711-717`, `co/rsk/trie/Trie.java:362-376`) |
| TRIE-HASH-05 | derived | **Legacy (Orchid) hash.** For non-empty n, getHashOrchid(s) == keccak256(toMessageOrchid(s)), where children are referenced by their Orchid hashes; for the empty node it returns the same EMPTY_HASH as getHash(). | `IPs/RSKIP107.md:32-44; RSKIP240.md:53` | **conforms**: Used for transaction and receipt roots before RSKIP126 (BlockHashesHelper). (`co/rsk/trie/Trie.java:381-395`, `co/rsk/trie/Trie.java:525-583`, `co/rsk/trie/NodeReference.java:132-134`, `co/rsk/core/bc/BlockHashesHelper.java:22-29`, `co/rsk/core/bc/BlockHashesHelper.java:76-83`) |

## SER: Serialization and parser

| ID | Kind | Statement | Citation | Java reading |
| --- | --- | --- | --- | --- |
| TRIE-SER-01 | derived | **Round trip of canonical nodes.** For every node n of a reachable trie (children loaded): m = n.toMessage(); fromMessage(m, store).toMessage() == m, and the parsed node has the same sharedPath, valueLength, valueHash, value (inline), childrenSize and child references (hash or equal embedded node). | `IPs/RSKIP107.md:50-85` | **conforms** (`co/rsk/trie/Trie.java:506-512`, `co/rsk/trie/Trie.java:677-739`, `co/rsk/trie/Trie.java:163-175`, `co/rsk/trie/Trie.java:259-347`, `co/rsk/trie/NodeReference.java:168-180`) |
| TRIE-SER-02 | derived | **Encoding is injective on canonical nodes.** For canonical nodes n1, n2 (TRIE-CMP-01, children loaded), n1.toMessage() == n2.toMessage() implies n1 and n2 have equal sharedPath, value, childrenSize and equal child references. | `IPs/RSKIP107.md:50-85` | **conforms**: Follows from TRIE-SER-01 (fromMessage is a left inverse). (`co/rsk/trie/Trie.java:677-739`) |
| TRIE-SER-03 | ambiguity | **Parser canonicity: child flags.** Canonical-parse reading: fromMessage rejects an embedded flag without the matching presence flag, and an embedded child that is the empty node. | `IPs/RSKIP107.md:56-57; 64-75` | **diverges**: The embedded bit is ignored when presence is clear; an embedded empty node collapses to NodeReference.EMPTY. (`co/rsk/trie/Trie.java:264-307`, `co/rsk/trie/NodeReference.java:44-55`) |
| TRIE-SER-04 | derived | **Format dispatch is unambiguous for canonical encodings.** toMessageOrchid(n)[0] == 0x02 and toMessage(n)[0] is in 0x40..0x7F, so fromMessage picks the right parser for every encoding Java produces. | `IPs/RSKIP240.md:53; RSKIP107.md:34,53` | **conforms** (`co/rsk/trie/Trie.java:163-175`, `co/rsk/trie/Trie.java:549`, `co/rsk/trie/Trie.java:693-694`) |
| TRIE-SER-05 | ambiguity | **Parser behaviour on malformed input.** For every byte string m, fromMessage(m, store) terminates and either returns a Trie or throws a RuntimeException; it never allocates more than O(\|m\|) memory. | `IPs/RSKIP107.md:50-85` | **unclear**: RSKIPs are silent on errors. Empty input throws ArrayIndexOutOfBoundsException (:166); truncation throws BufferUnderflowException; bad sizes throw IllegalArgumentException. Allocation is not bounded by \|m\|: SharedPathSerializer.deserialize allocates byte[ceil(lshared/8)] from an attacker-chosen VarInt before checking the buffer. (`co/rsk/trie/Trie.java:163-347`, `co/rsk/trie/SharedPathSerializer.java:120-148`, `co/rsk/trie/PathEncoder.java:75-88`) |
| TRIE-SER-06 | requirement | **Legacy (Orchid) layout.** toMessageOrchid(s) = 0x02 ++ flags (bit0 secure, bit1 hasLongValue) ++ uint16 child bitmask (bit0 left, bit1 right) ++ int16 lshared ++ encodedSharedPath (if lshared > 0) ++ left hash ++ right hash ++ (valueHash if hasLongValue else value). | `IPs/RSKIP107.md:32-44` | **conforms**: The RSKIP gives no bit positions for secure/hasLongValue and no byte order for the 16-bit fields; Java uses bits 0/1 and big-endian. (`co/rsk/trie/Trie.java:525-583`) |
| TRIE-SER-07 | derived | **Legacy (Orchid) parser.** For every node n without long value, fromMessageOrchid(toMessageOrchid(s)) has n's sharedPath and value and references the children by their Orchid hashes; with a long value, it retrieves the value from the store by valueHash. | `IPs/RSKIP107.md:32-44` | **conforms**: Notes: trailing bytes after valueHash are ignored; a missing long value in the store causes a NullPointerException at :233; inline values longer than 32 bytes are accepted. (`co/rsk/trie/Trie.java:177-257`) |
| TRIE-SER-08 | derived | **TrieDTO agrees with Trie on the node format.** For every canonical encoding m, TrieDTO.decodeFromMessage(m, store).toMessage() == m and its flags, path, child references, childrenSize and value agree with Trie.fromMessage(m, store). | `IPs/RSKIP107.md:50-85` | **unclear**: Second parser used by snapshot sync; not fully read for this spec. (`co/rsk/trie/TrieDTO.java:83-158`, `co/rsk/trie/TrieDTO.java:417-448`) |

## SIZE: treeSize / childrenSize

| ID | Kind | Statement | Citation | Java reading |
| --- | --- | --- | --- | --- |
| TRIE-SIZE-01 | ambiguity | **Meaning of treeSize.** For every node n of a reachable trie, n.getChildrenSize().value == sum over children c of (c.getMessageLength() + c.getChildrenSize().value + (c.hasLongValue() ? c.getValueLength() : 0)), and 0 for a terminal node. | `IPs/RSKIP107.md:82; 93` | **conforms**: RSKIP107 says only 'the size of the tree'. Java: bytes of all serialized descendants plus their external long values, excluding the node itself; embedded children are counted in their own message length. (`co/rsk/trie/Trie.java:1001-1011`, `co/rsk/trie/NodeReference.java:188-195`) |
| TRIE-SIZE-02 | derived | **Incremental childrenSize equals recomputation.** For every node of a reachable trie, the childrenSize carried through internalPut, split and delete coalescing equals the value getChildrenSize() computes from scratch (TRIE-SIZE-01) on a copy of the node built with childrenSize = null. | `IPs/RSKIP107.md:82` | **conforms** (`co/rsk/trie/Trie.java:891-916`, `co/rsk/trie/Trie.java:919-940`, `co/rsk/trie/Trie.java:818-820`, `co/rsk/trie/Trie.java:859-868`) |
| TRIE-SIZE-03 | ambiguity | **Parser does not validate treeSize.** Canonical-parse reading: fromMessage rejects a node whose treeSize differs from TRIE-SIZE-01 applied to its children. | `IPs/RSKIP107.md:82` | **diverges**: The parsed value is stored as-is and propagated by later incremental updates. (`co/rsk/trie/Trie.java:309-312`, `co/rsk/trie/Trie.java:1001-1011`) |

## STORE: TrieStore

| ID | Kind | Statement | Citation | Java reading |
| --- | --- | --- | --- | --- |
| TRIE-STORE-01 | derived | **Save/retrieve round trip.** For a reachable trie t over TrieStoreImpl s: after s.save(t), s.retrieve(t.getHash().getBytes()) is present and yields t' with t'.getHash() == t.getHash() and the same get results for every key. | `IPs/RSKIP24.md:78; RSKIP107.md:66` | **conforms** (`co/rsk/trie/TrieStoreImpl.java:57-145`, `co/rsk/trie/TrieStoreImpl.java:152-168`) |
| TRIE-STORE-02 | derived | **Store is content-addressed.** After s.save(t), every entry (h -> m) written for a node satisfies h == keccak256(m), and every non-embedded child hash in a saved node resolves to that child's encoding. | `IPs/RSKIP107.md:66; RSKIP24.md:78` | **diverges**: Holds for every non-empty node. The empty root is stored under EMPTY_HASH = keccak256(0x80) with value 0x40 (TRIE-HASH-02), so h != keccak256(m) for that entry. (`co/rsk/trie/TrieStoreImpl.java:99`, `co/rsk/trie/TrieStoreImpl.java:141`) |
| TRIE-STORE-03 | derived | **Embedded nodes are not stored separately.** s.save(t) writes an entry for the root and for every non-embedded node reachable through loaded references, and no entry for an embedded non-root node. | `IPs/RSKIP107.md:26; 89` | **conforms**: The root is written even when embeddable (:135). (`co/rsk/trie/TrieStoreImpl.java:92-145`) |
| TRIE-STORE-04 | derived | **Long values are stored by hash.** After s.save(t), for every node with hasLongValue, s.retrieveValue(valueHash) == value and valueHash == keccak256(value). | `IPs/RSKIP240.md:85; RSKIP107.md:76-77` | **conforms**: Values share the node keyspace (comment :121-129). (`co/rsk/trie/TrieStoreImpl.java:120-133`, `co/rsk/trie/TrieStoreImpl.java:210-225`) |
| TRIE-STORE-05 | requirement | **Epoch stores: write newest, read newest to oldest.** MultiTrieStore.save/saveValue write only to the current epoch store; retrieve/retrieveValue return the entry from the newest epoch that has it. | `IPs/RSKIP64.md:38; 41` | **conforms** (`co/rsk/trie/MultiTrieStore.java:60-72`, `co/rsk/trie/MultiTrieStore.java:88-122`) |
| TRIE-STORE-06 | requirement | **Epoch migration keeps live nodes.** After MultiTrieStore.collect(r), every node and long value reachable from root r is still retrievable (entries only in the oldest epoch are copied to the next one before it is disposed). | `IPs/RSKIP64.md:47-53` | **diverges**: collect retrieves r (marked saved by retrieve, :94) and calls save on it; TrieStoreImpl.save returns at once for saved nodes and only walks loaded children, so nothing is copied. (`co/rsk/trie/MultiTrieStore.java:137-150`, `co/rsk/trie/MultiTrieStore.java:94`, `co/rsk/trie/TrieStoreImpl.java:93-95`, `co/rsk/trie/TrieStoreImpl.java:108-118`) |

## Ambiguities and suspected divergences

Every obligation of kind `ambiguity` or with Java reading `diverges`/`unclear`, with its reproducer hint. Hints marked *Sanity run* were run against the real classes by `sanity/ReproHints.jsh` (output: `sanity/ReproHints.out`). That run only confirms the hint behaves as described; it is not a verification result.

### TRIE-KEY-02: Hash-prefix slice notation [0:9] / [0..9] vs 80 bits (ambiguity, Java conforms)

- RSKIP: `IPs/RSKIP108.md:61-64; 32` (Specification (key mapping table))
- Quote:

  > | 0x00<br />SHA3(account_addr)[0:9]<br />account_addr          | rlp(nonce,amount,flags) | account state                              |
  > | 0x00<br />SHA3(account_addr)[0:9]<br />account_addr<br />0x00<br />SHA3(storage_address)[0..9]   trimmed_storage_address | byte array              | value at a storage cell                    |
  > ...
  > Therefore a 80-bit hash digest prefix is more than enough

- Statement: The hash prefix in account and storage keys is exactly 10 bytes: TrieKeyMapper.secureKeyPrefix(x).length == 10 and == keccak256(x)[0..10).
- Java: **conforms**: Readings: (a) [0:9] half-open = 9 bytes (72 bits); (b) inclusive 0..9 = 10 bytes (80 bits). The prose says 80 bits and 'account trie keys consuming only 30 bytes' (10+20), so (b); Java implements (b). (`org/ethereum/db/TrieKeyMapper.java:38`, `org/ethereum/db/TrieKeyMapper.java:77-79`)
- Reproducer: Compare secureKeyPrefix(addr).length (10) with the literal half-open reading (9).
- Notes: Record as a finding on the RSKIP text; Java follows the prose.

### TRIE-KEY-05: Storage-root placeholder value is 0x00 (requirement, Java diverges)

- RSKIP: `IPs/RSKIP108.md:63` (Specification)
- Quote:

  > | 0x00<br />SHA3(account_addr)[0:9]<br />account_addr<br />0x00 | 0x00                    | placeholder for isolating the storage tree |

- Statement: When an account's storage subtree is created, the value stored at getAccountStoragePrefixKey(a) is the single byte 0x00.
- Java: **diverges**: MutableRepository writes ONE_BYTE_ARRAY = {0x01} at the storage prefix key (and the comment at :394 says 'The value should be ONE_BYTE_ARRAY'). (`org/ethereum/db/MutableRepository.java:56`, `org/ethereum/db/MutableRepository.java:107-108`, `org/ethereum/db/MutableRepository.java:392-395`)
- Reproducer: Create a contract storage row through MutableRepository.addStorageBytes and read trie.get(getAccountStoragePrefixKey(a)): returns 01, RSKIP108 table says 00. The value is part of the consensus state root.
- Notes: Outside co.rsk.trie (repository layer) but it fixes bytes that enter the Unitrie root hash. JBMC/Lean may treat it as a key-mapping finding only.

### TRIE-KEY-07: Hash input of the storage-address prefix (ambiguity, Java unclear)

- RSKIP: `IPs/RSKIP108.md:64; 34` (Specification)
- Quote:

  > | 0x00<br />SHA3(account_addr)[0:9]<br />account_addr<br />0x00<br />SHA3(storage_address)[0..9]   trimmed_storage_address | byte array              | value at a storage cell                    |
  > ...
  > Therefore we can compress keys by removing all leading zeros

- Statement: The 10-byte storage prefix is keccak256 of the full 32-byte storage address (not of trimmed_storage_address).
- Java: **unclear**: Readings: SHA3 over (a) the 256-bit address as a 32-byte word, or (b) the trimmed address. Java uses (a); its own comment at :70 asks 'should we hash the full subkey or the stripped one?'. (`org/ethereum/db/TrieKeyMapper.java:69-73`)
- Reproducer: Slot 1: Java prefix = keccak256(0x00..01 (32 bytes))[0..10); reading (b) would use keccak256(0x01)[0..10).

### TRIE-KEY-10: RSKIP112 value type specifiers (requirement, Java diverges)

- RSKIP: `IPs/RSKIP112.md:35-42` (Specification)
- Quote:

  > The non-zero values in the trie are prefixed by the following type specifier as a single byte:
  > 
  > - A for account or contract
  > - S for contract storage cell
  > - R for contract storage trie root
  > - D for coDe (C is reserved in case contracts are assigned their own type specifier)
  > 
  > Specifiers are shown in ASCII.

- Statement: Every non-zero value stored in the Unitrie starts with one ASCII type byte: 'A' account, 'S' storage cell, 'R' storage root, 'D' code.
- Java: **diverges**: rskj stores raw values (account RLP, code bytes, stripped storage words, 0x01 placeholder) with no type byte. (`org/ethereum/db/MutableRepository.java:56`, `org/ethereum/db/MutableRepository.java:107-108`, `org/ethereum/db/MutableRepository.java:252-255`)
- Reproducer: Any account value read from a Java-built state trie does not start with 'A' (0x41).
- Notes: Recorded so the matrix can mark it not-applicable (Draft, not activated) rather than silently dropping it.

### TRIE-PATH-01: Key bytes to bit path: MSB first (ambiguity, Java unclear)

- RSKIP: `IPs/RSKIP107.md:39; RSKIP16.md:58` (Motivation; Trie Path Components)
- Quote:

  > - **lshared**, int16 (2 bytes): length of shared prefix in bits
  > Each key in the trie is split into the four parts:

- Statement: TrieKeySlice.fromKey(k) is the bit string of length 8*|k| where bit 8i+j is bit (7-j) of k[i] (most significant bit first).
- Java: **unclear**: RSKIPs count the shared prefix in bits but never fix the bit order inside a key byte. Java: MSB first (PathEncoder comments ':48 First bit is MOST SIGNIFICANT'). TrieKeyMapper.java:43-44 relies on it ('This makes the MSB 0/1 be branching'). (`co/rsk/trie/TrieKeySlice.java:109-115`, `co/rsk/trie/PathEncoder.java:72-88`)
- Reproducer: fromKey([0x80]) = [1,0,0,0,0,0,0,0].
- Notes: Record Java's choice as the finding; all hashes depend on it.

### TRIE-PATH-02: Implicit branch bit; 0 = left, 1 = right (ambiguity, Java unclear)

- RSKIP: `IPs/RSKIP107.md:36-38` (Motivation (old format presence bitmask))
- Quote:

  > - **bits**: 2 bytes: child presence bitmask
  >   - bit 0: left node present
  >   - bit 1: right node present

- Statement: A node's full key is parentKey ++ [b] ++ sharedPath where b is 0 for the left child and 1 for the right child; b is not stored in the child's shared path. find/put descend with getNodeReference(b), b = key.get(sharedPath.length()).
- Java: **unclear**: No RSKIP states that the branch bit is implicit or which bit value selects left. Java: bit 0 -> left, bit 1 -> right, bit implicit. (`co/rsk/trie/Trie.java:669`, `co/rsk/trie/Trie.java:749-751`, `co/rsk/trie/Trie.java:875-884`, `co/rsk/trie/Trie.java:612`, `co/rsk/trie/TrieKeySlice.java:86-97`)
- Reproducer: put(0x00,..) and put(0x80,..) from the empty trie: the 0x00 entry becomes the left child with a 7-bit shared path.

### TRIE-PATH-03: encodedSharedPath packing (ambiguity, Java conforms)

- RSKIP: `IPs/RSKIP107.md:61-63` (Specification (node format))
- Quote:

  > - if lshared>0
  > 
  >   - **encodedSharedPath**, variable: shared prefix

- Statement: PathEncoder.encode(p) has length ceil(|p|/8) (calculateEncodedLength), packs bits MSB first, sets padding bits to 0, and PathEncoder.decode(encode(p), |p|) == p.
- Java: **conforms**: The RSKIP gives no packing; conforms to the MSB-first, zero-padded reading. (`co/rsk/trie/PathEncoder.java:49-70`, `co/rsk/trie/PathEncoder.java:75-88`, `co/rsk/trie/PathEncoder.java:90-92`, `co/rsk/trie/TrieKeySlice.java:45-48`, `co/rsk/trie/TrieKeySlice.java:117-122`)

### TRIE-PATH-04: Parser ignores non-zero padding bits (ambiguity, Java diverges)

- RSKIP: `IPs/RSKIP107.md:61-63` (Specification (node format))
- Quote:

  > - if lshared>0
  > 
  >   - **encodedSharedPath**, variable: shared prefix

- Statement: Canonical-parse reading: Trie.fromMessage rejects an encodedSharedPath whose padding bits (beyond lshared) are not zero.
- Java: **diverges**: decodeBinaryPath reads only the first lshared bits; padding is ignored, so two byte strings parse to the same node and getHash() != keccak256(message). (`co/rsk/trie/PathEncoder.java:75-88`, `co/rsk/trie/SharedPathSerializer.java:137-148`, `co/rsk/trie/Trie.java:269`)
- Reproducer: Sanity run: fromMessage(5000ff01).toMessage() == 50008001.

### TRIE-LSH-03: Escape 255 + Bitcoin VarInt for other lengths (ambiguity, Java conforms)

- RSKIP: `IPs/RSKIP107.md:101; 103` (Shared Prefix Size Compression)
- Quote:

  > - 255: use from 1 to 9 additional bytes (following) to a Bitcoin VarInt
  > ...
  > In the extreme case a sufficiently long prefix collision appears, the third option (2 additional bytes) is used.

- Statement: For l in 33..159 or l >= 383, serializeBytes writes 0xFF followed by VarInt(l).encode() (the VarInt carries l itself); calculateVarIntSize(l) == 1 + VarInt.sizeOf(l).
- Java: **conforms**: RSKIP leaves open what the VarInt encodes (l, or l minus an offset) and says '2 additional bytes' while VarInt takes 1..9. Java: VarInt(l); l in 33..159 costs 2 bytes in total (marker + 1). (`co/rsk/trie/SharedPathSerializer.java:72-75`, `co/rsk/trie/SharedPathSerializer.java:104-114`, `co/rsk/trie/SharedPathSerializer.java:131-133`)
- Reproducer: l = 33 -> ff21; l = 159 -> ff9f; l = 383 -> fffd7f01.
- Notes: Lengths 33..159 are not covered by either compact range; the text only covers them through the escape.

### TRIE-LSH-06: Parser accepts non-canonical lshared encodings (ambiguity, Java diverges)

- RSKIP: `IPs/RSKIP107.md:97-101` (Shared Prefix Size Compression)
- Quote:

  > Let lshared be the actual length of the prefix. The lsharedCompressed expands to lshared as follows:
  > 
  > - range 0..31: lshared = lsharedCompressed  + 1
  > - range 32..254: lshared = lsharedCompressed + 128
  > - 255: use from 1 to 9 additional bytes (following) to a Bitcoin VarInt

- Statement: Canonical-parse reading: getPathBitsLength accepts the escape form only for lengths outside 1..32 and 160..382, only minimal VarInts, only values that fit in an int, and never lshared = 0 with sharedPrefixPresent set.
- Java: **diverges**: All four non-canonical forms are accepted; the 9-byte VarInt is truncated by the (int) cast at :132. (`co/rsk/trie/SharedPathSerializer.java:120-135`, `co/rsk/trie/SharedPathSerializer.java:167-183`, `co/rsk/trie/Trie.java:263`, `co/rsk/trie/Trie.java:269`)
- Reproducer: Sanity run (each re-serializes differently): 50ff050001 -> 50040001; 50fffd05000001 -> 50040001; 50ffff05000000010000000001 (VarInt 2^32+5) -> 50040001; 50ff0001 (lshared 0) -> 4001.

### TRIE-VARINT-03: Non-minimal VarInt accepted (ambiguity, Java diverges)

- RSKIP: `IPs/RSKIP107.md:109-114` (Variable length integer)
- Quote:

  > | Value          | Storage length | Format                                  |
  > | -------------- | -------------- | --------------------------------------- |
  > | < 0xFD         | 1              | uint8_t                                 |
  > | <= 0xFFFF      | 3              | 0xFD followed by the length as uint16_t |
  > | <= 0xFFFF FFFF | 5              | 0xFE followed by the length as uint32_t |
  > | -              | 9              | 0xFF followed by the length as uint64_t |

- Statement: Canonical-parse reading: the node parser rejects a VarInt (treeSize or escaped lshared) that is longer than VarInt.sizeOf(value).
- Java: **diverges**: bitcoinj VarInt(byte[],int) has no minimality check. (co.rsk.bitcoinj.core.VarInt (bitcoinj-thin-0.14.4-rsk-18.jar, decompiled with javap -c: VarInt(long), VarInt(byte[],int), sizeOf, encode), `co/rsk/trie/Trie.java:1149-1165`, `co/rsk/trie/SharedPathSerializer.java:167-183`)
- Reproducer: Sanity run: fromMessage(5a07000450060002fd040001).toMessage() == 5a070004500600020401 (treeSize 4 written as fd0400).

### TRIE-NODE-02: Parser dispatch on version (ambiguity, Java diverges)

- RSKIP: `IPs/RSKIP240.md:53; RSKIP107.md:53` (Trie node versioning)
- Quote:

  > We can use version number 0 for Orchid encoding, 1 for the current encoding (RSKIP107), and 2 for nodes with rent time stamp (current proposal).
  >   - **NodeVersion**: 2 bits indicate serialization version (bits 6,7). Currently 01 (bit 6=1).

- Statement: fromMessage parses a message as RSKIP107 only if flags bits 6-7 == 01 and rejects versions 10 and 11 (rent format is not implemented); version-00 input other than an Orchid node (first byte 0x02) is rejected.
- Java: **diverges**: Java selects Orchid iff message[0] == 0x02 and otherwise parses as RSKIP107 without reading the version bits ('if we reached here, we don't need to check the version flag'). (`co/rsk/trie/Trie.java:163-175`, `co/rsk/trie/Trie.java:259-261`)
- Reproducer: Sanity run: c001 -> 4001, 8001 -> 4001, 00 -> 40, 0101 -> 4001 (all accepted as RSKIP107 nodes).
- Notes: RSKIP107 alone only defines version 01, so it does not say what a parser must do with other versions; RSKIP240's numbering makes versions 00/10/11 distinct formats.

### TRIE-NODE-04: Child presence/embedding flag bits (ambiguity, Java diverges)

- RSKIP: `IPs/RSKIP107.md:56-57; 64-75` (Specification (node format))
- Quote:

  >   - **nodePresent**: 2 bits indicate left/right embedded node (bit 2 = left, bit 3 = right)
  >   - **nodeIsEmbedded**: 2 bits indicate left/right node presence (bit 0 = left, bit 1=right)
  > ...
  > - if nodePresent[0]
  >   - if  !nodeIsEmbedded[0]:

- Statement: The four low flag bits follow the RSKIP: presence of left/right and embedding of left/right at the bit positions the text assigns.
- Java: **diverges**: The text swaps names and descriptions (nodePresent is described as 'embedded', nodeIsEmbedded as 'presence'); the conditional layout at :64-75 uses nodePresent as presence. Reading A (by name): present L=bit2 R=bit3, embedded L=bit0 R=bit1. Reading B (by description): embedded L=bit2 R=bit3, present L=bit0 R=bit1. Java: present L=bit3 (0x08) R=bit2 (0x04), embedded L=bit1 (0x02) R=bit0 (0x01); this matches neither reading (it is reading A with left/right exchanged). (`co/rsk/trie/Trie.java:703-717`, `co/rsk/trie/Trie.java:264-267`)
- Reproducer: Sanity run: trie {00:01, 0000:02} root = 5a070004500600020401: flags 0x5a (version 0x40, prefix 0x10, left present 0x08, left embedded 0x02). Both RSKIP readings give 0x55 here (A: present-left bit2 0x04 + embedded-left bit0 0x01; B: present-left bit0 0x01 + embedded-left bit2 0x04). A left child referenced by hash separates A (0x04) from B (0x01); Java writes 0x08.

### TRIE-NODE-07: treeSize presence condition (ambiguity, Java diverges)

- RSKIP: `IPs/RSKIP107.md:80-82` (Specification (node format))
- Quote:

  > - if the left and right nodes are not present:
  > 
  >   - **treeSize**, 0-9 bytes: the size of the tree, variable length integer

- Statement: Literal reading: treeSize is written iff the node has no children. Java: childrenSize VarInt is written iff the node has at least one child.
- Java: **diverges**: Java does the opposite of the literal text; the literal condition makes treeSize ('the size of the tree') meaningless for leaves, so the text is probably negated by mistake. (`co/rsk/trie/Trie.java:689`, `co/rsk/trie/Trie.java:727-729`, `co/rsk/trie/Trie.java:309-312`)
- Reproducer: Sanity run: 43-byte leaves carry no treeSize, root of the same trie carries childrenSize 86 (=2*43).

### TRIE-NODE-08: treeSize position relative to long-value fields (ambiguity, Java diverges)

- RSKIP: `IPs/RSKIP107.md:76-82` (Specification (node format))
- Quote:

  > - if hasLongVal:
  >   - **valueHash**, 32 bytes: Hash digest of value stored
  >   - **valueLength**, uint24 (3 bytes): size of the value contained (if lvalue>0 and hasLongVal)
  > 
  > - if the left and right nodes are not present:
  > 
  >   - **treeSize**, 0-9 bytes: the size of the tree, variable length integer

- Statement: Literal order: ... right reference, valueHash, valueLength, treeSize, value. Java order: ... right reference, childrenSize, valueHash, valueLength | value.
- Java: **diverges**: For a node with children and a long value, Java writes childrenSize before valueHash; the RSKIP lists treeSize after valueLength. (`co/rsk/trie/Trie.java:727-736`, `co/rsk/trie/Trie.java:309-338`)
- Reproducer: Sanity run: trie {01: 33x0xab, 0101: 02} root = 7a 07 01 04 50060202 04 <keccak256(33x0xab)> 000021; childrenSize 04 precedes the value hash.

### TRIE-EMB-02: Parser accepts non-terminal embedded nodes (ambiguity, Java diverges)

- RSKIP: `IPs/RSKIP107.md:118-120` (Recursive Embedding)
- Quote:

  > we limit that embedded nodes must be terminal (they cannot contain child nodes, even if small)

- Statement: Canonical-parse reading: fromMessage rejects a message whose embedded child has a child.
- Java: **diverges**: Embedded bytes are parsed recursively with no terminal check (and recursion depth is bounded only by the uint8 sizes). (`co/rsk/trie/Trie.java:273-282`, `co/rsk/trie/Trie.java:291-300`)
- Reproducer: Sanity run: 4a22 48<32x0x11>00 00 parses; toMessage = 48 <keccak256(inner)> 00 (child re-encoded by hash).

### TRIE-EMB-03: Embedding size limit: 40 vs 44 bytes (ambiguity, Java diverges)

- RSKIP: `IPs/RSKIP107.md:68-69; 74-75; RSKIP242.md:27; RSKIP244.md:33` (Specification (node format))
- Quote:

  >     - **leftNodeEncoded**, up to 40 bytes: left node encoded
  > when installing 44 or less bytes of code, those bytes are stored in the trie node (without a hash digest indirection)
  > storage cells of 44 bytes or less are embedded in parent trie nodes

- Statement: RSKIP107 reading: an embedded child encoding is at most 40 bytes. Java embeds a terminal child iff getMessageLength() <= 44.
- Java: **diverges**: Diverges from RSKIP107 (40); agrees with the 44 stated in RSKIP242/244 (Draft). (`co/rsk/trie/Trie.java:68`, `co/rsk/trie/Trie.java:587-589`)
- Reproducer: Sanity run: keys 00||7x00 and 80||7x00 with 32-byte values: leaves are 43 bytes and are embedded (root flags 0x4f, size byte 0x2b).

### TRIE-EMB-04: Embedding is determined by the child's content (ambiguity, Java conforms)

- RSKIP: `IPs/RSKIP107.md:57; 64-75` (Specification (node format))
- Quote:

  >   - **nodeIsEmbedded**: 2 bits indicate left/right node presence (bit 0 = left, bit 1=right)
  >   - if nodeIsEmbedded[0]:
  >     - **leftNodeSize**, uint8, 1 byte
  >     - **leftNodeEncoded**, up to 40 bytes: left node encoded

- Statement: For every node of a trie built from new Trie() by put/delete, a child is serialized embedded iff it is terminal and its getMessageLength() <= 44 (a function of the child alone).
- Java: **conforms**: RSKIP107 only says a flag 'indicates' embedding and never makes it mandatory. Java also requires the child object to be loaded (NodeReference.isEmbeddable returns false when lazyNode == null), which holds for in-memory tries but not for parsed ones; see TRIE-HASH-04. (`co/rsk/trie/NodeReference.java:141-148`, `co/rsk/trie/NodeReference.java:156-180`, `co/rsk/trie/Trie.java:587-589`)

### TRIE-VAL-03: valueHash is Keccak-256 of the value (ambiguity, Java conforms)

- RSKIP: `IPs/RSKIP107.md:77` (Specification (node format))
- Quote:

  >   - **valueHash**, 32 bytes: Hash digest of value stored

- Statement: For every node with a value, getValueHash() == keccak256(getValue()).
- Java: **conforms**: 'Hash digest' is not named; Java uses Keccak-256 (RSK's SHA3). (`co/rsk/trie/Trie.java:975-983`, `co/rsk/trie/Trie.java:331`)

### TRIE-VAL-04: valueLength byte order (ambiguity, Java unclear)

- RSKIP: `IPs/RSKIP107.md:78; 107` (Specification; Variable length integer)
- Quote:

  >   - **valueLength**, uint24 (3 bytes): size of the value contained (if lvalue>0 and hasLongVal)
  > ...
  > Integer can be encoded depending on the represented value to save space. Longer numbers are encoded in little endian.

- Statement: valueLength is encoded big-endian: Uint24(n).encode() == [n>>16, n>>8, n] (low bytes).
- Java: **unclear**: If 'Longer numbers are encoded in little endian' (said in the VarInt paragraph) applies to uint24 fields, Java diverges; if it only concerns VarInt, the RSKIP is silent and Java chose big-endian. (`co/rsk/core/types/ints/Uint24.java:38-44`, `co/rsk/core/types/ints/Uint24.java:79-84`)
- Reproducer: 33-byte value -> Java 000021; little-endian reading -> 210000.

### TRIE-VAL-05: Parser accepts non-canonical value encodings (ambiguity, Java diverges)

- RSKIP: `IPs/RSKIP107.md:54; 76-85` (Specification (node format))
- Quote:

  >   - **hasLongValue**: 1 bit indicate if value length > 32 bytes (bit 5)

- Statement: Canonical-parse reading: fromMessage rejects an inline value longer than 32 bytes and a long-value encoding with valueLength <= 32.
- Java: **diverges**: Both are accepted; the node then re-serializes in the other form. (`co/rsk/trie/Trie.java:318-338`)
- Reproducer: Sanity run: 40||33x00 -> 60<keccak>000021; 60||32xaa||000001 parses with valueLength 1, hasLongValue false; 60||32xaa||000000 parses to an empty node (toMessage 40).

### TRIE-VAL-06: Lazily retrieved long value matches valueHash (derived, Java diverges)

- RSKIP: `IPs/RSKIP107.md:77-78` (Specification (node format))
- Quote:

  >   - **valueHash**, 32 bytes: Hash digest of value stored
  >   - **valueLength**, uint24 (3 bytes): size of the value contained (if lvalue>0 and hasLongVal)

- Statement: For a node parsed from a store, getValue() returns v with keccak256(v) == getValueHash() and |v| == getValueLength(), or throws.
- Java: **diverges**: Only the length is checked after retrieval; a store entry of the right length but wrong content is returned silently. Holds when the store is content-addressed (TRIE-STORE-04). (`co/rsk/trie/Trie.java:985-992`, `co/rsk/trie/Trie.java:1013-1037`)
- Reproducer: Store H -> v' with |v'| == |v| and v' != v under a node whose valueHash is H: getValue() returns v'.
- Notes: Matters for the JBMC store model: an arbitrary store can violate it.

### TRIE-HASH-01: Node hash is Keccak-256 of the RSKIP107 encoding (ambiguity, Java conforms)

- RSKIP: `IPs/RSKIP107.md:26; 66` (Abstract; node format)
- Quote:

  > plus the hash digest of the parent node referencing the node
  >     - **leftNodeHash**, 32 bytes: left node hash

- Statement: For every non-empty node n, n.getHash() == keccak256(n.toMessage()).
- Java: **conforms**: Neither the hash function nor its preimage is specified; Java hashes toMessage() with Keccak-256. (`co/rsk/trie/Trie.java:362-376`)

### TRIE-HASH-02: Empty-trie hash (ambiguity, Java unclear)

- RSKIP: `IPs/RSKIP107.md:50-85` (Specification (node format))
- Quote:

  > The new node format is as follows:
  > 
  > - flags, 1 byte: indicates the type of node

- Statement: new Trie().getHash() == keccak256(RLP.encodeElement([])) == keccak256(0x80) = 56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421, whereas new Trie().toMessage() == 0x40 and keccak256(0x40) = e724d40619441ced66a271e59627b7bcd39c77447a4315561b4d21e7b7c9321c.
- Java: **unclear**: No RSKIP defines the empty root. Java special-cases it (Ethereum's empty-trie root) instead of hashing the encoding, so TRIE-HASH-01 excludes the empty node. (`co/rsk/trie/Trie.java:75`, `co/rsk/trie/Trie.java:367-369`, `co/rsk/trie/Trie.java:1088-1090`)
- Reproducer: Sanity run confirms both values.

### TRIE-HASH-04: Hash independent of lazy loading (derived, Java diverges)

- RSKIP: `IPs/RSKIP24.md:76; 54` (Motivation)
- Quote:

  > Note that the hashes of the nodes are not computed immediately, but lazy-computed, only when they are required by the user.
  > 3. Authenticated Data structure

- Statement: For any node t parsed from a store, t.getHash() does not depend on which children were loaded (via get/find/getNode) before getHash() is first called.
- Java: **diverges**: NodeReference.isEmbeddable depends on whether the child object is cached. For stores written by TrieStoreImpl.save this cannot trigger (an embeddable child is never stored by hash); it does for store content that references an embeddable terminal child by hash. (`co/rsk/trie/NodeReference.java:141-148`, `co/rsk/trie/NodeReference.java:103-126`, `co/rsk/trie/Trie.java:711-717`, `co/rsk/trie/Trie.java:362-376`)
- Reproducer: Sanity run: store keccak(C) -> C = 50060001; parent P = 48 ++ keccak(C) ++ 04. fromMessage(P).getHash() = keccak(P) = 04f34ee9...; after t.get(00) on a fresh parse, getHash() = d8921fa4... and toMessage() = 4a045006000104.

### TRIE-SER-03: Parser canonicity: child flags (ambiguity, Java diverges)

- RSKIP: `IPs/RSKIP107.md:56-57; 64-75` (Specification (node format))
- Quote:

  >   - **nodePresent**: 2 bits indicate left/right embedded node (bit 2 = left, bit 3 = right)
  >   - **nodeIsEmbedded**: 2 bits indicate left/right node presence (bit 0 = left, bit 1=right)
  > ...
  > - if nodePresent[0]
  >   - if  !nodeIsEmbedded[0]:
  >     - **leftNodeHash**, 32 bytes: left node hash
  >   - if nodeIsEmbedded[0]:
  >     - **leftNodeSize**, uint8, 1 byte
  >     - **leftNodeEncoded**, up to 40 bytes: left node encoded

- Statement: Canonical-parse reading: fromMessage rejects an embedded flag without the matching presence flag, and an embedded child that is the empty node.
- Java: **diverges**: The embedded bit is ignored when presence is clear; an embedded empty node collapses to NodeReference.EMPTY. (`co/rsk/trie/Trie.java:264-307`, `co/rsk/trie/NodeReference.java:44-55`)
- Reproducer: Sanity run: 4201 -> 4001; 4a01400001 -> 4001.
- Notes: Other non-canonical inputs are listed under PATH-04, LSH-06, VARINT-03, NODE-02, EMB-02, VAL-05, SIZE-03.

### TRIE-SER-05: Parser behaviour on malformed input (ambiguity, Java unclear)

- RSKIP: `IPs/RSKIP107.md:50-85` (Specification (node format))
- Quote:

  > The new node format is as follows:
  > 

- Statement: For every byte string m, fromMessage(m, store) terminates and either returns a Trie or throws a RuntimeException; it never allocates more than O(|m|) memory.
- Java: **unclear**: RSKIPs are silent on errors. Empty input throws ArrayIndexOutOfBoundsException (:166); truncation throws BufferUnderflowException; bad sizes throw IllegalArgumentException. Allocation is not bounded by |m|: SharedPathSerializer.deserialize allocates byte[ceil(lshared/8)] from an attacker-chosen VarInt before checking the buffer. (`co/rsk/trie/Trie.java:163-347`, `co/rsk/trie/SharedPathSerializer.java:120-148`, `co/rsk/trie/PathEncoder.java:75-88`)
- Reproducer: 50 ff fe ffffff7f (lshared = 2^31-1): allocates ~268 MB before BufferUnderflowException (not run).

### TRIE-SER-08: TrieDTO agrees with Trie on the node format (derived, Java unclear)

- RSKIP: `IPs/RSKIP107.md:50-85` (Specification (node format))
- Quote:

  > The new node format is as follows:
  > 

- Statement: For every canonical encoding m, TrieDTO.decodeFromMessage(m, store).toMessage() == m and its flags, path, child references, childrenSize and value agree with Trie.fromMessage(m, store).
- Java: **unclear**: Second parser used by snapshot sync; not fully read for this spec. (`co/rsk/trie/TrieDTO.java:83-158`, `co/rsk/trie/TrieDTO.java:417-448`)
- Notes: Lower priority; include if the helpers have capacity.

### TRIE-SIZE-01: Meaning of treeSize (ambiguity, Java conforms)

- RSKIP: `IPs/RSKIP107.md:82; 93` (Specification (node format))
- Quote:

  >   - **treeSize**, 0-9 bytes: the size of the tree, variable length integer
  > The value treeSize enables sharding the state tree between nodes and requesting pieces in parallel from different nodes by specifying and offset and size of the requested chunk, while still being able to validate each piece independently, without the need to collect all pieces first.

- Statement: For every node n of a reachable trie, n.getChildrenSize().value == sum over children c of (c.getMessageLength() + c.getChildrenSize().value + (c.hasLongValue() ? c.getValueLength() : 0)), and 0 for a terminal node.
- Java: **conforms**: RSKIP107 says only 'the size of the tree'. Java: bytes of all serialized descendants plus their external long values, excluding the node itself; embedded children are counted in their own message length. (`co/rsk/trie/Trie.java:1001-1011`, `co/rsk/trie/NodeReference.java:188-195`)
- Reproducer: Sanity run: root of two 43-byte embedded leaves has childrenSize 86.

### TRIE-SIZE-03: Parser does not validate treeSize (ambiguity, Java diverges)

- RSKIP: `IPs/RSKIP107.md:82` (Specification (node format))
- Quote:

  >   - **treeSize**, 0-9 bytes: the size of the tree, variable length integer

- Statement: Canonical-parse reading: fromMessage rejects a node whose treeSize differs from TRIE-SIZE-01 applied to its children.
- Java: **diverges**: The parsed value is stored as-is and propagated by later incremental updates. (`co/rsk/trie/Trie.java:309-312`, `co/rsk/trie/Trie.java:1001-1011`)
- Reproducer: Sanity run: fromMessage(5a070004500600020501).getChildrenSize() == 5; the correct value is 4.

### TRIE-STORE-02: Store is content-addressed (derived, Java diverges)

- RSKIP: `IPs/RSKIP107.md:66; RSKIP24.md:78` (Specification (node format))
- Quote:

  >     - **leftNodeHash**, 32 bytes: left node hash
  > This implementation assumes that the full tree can be kept in memory, and when a branch of the trie has not been used it can be kept in SSD disk, by adding to the tree a placeholder that references the remaining part to be loaded from disk.

- Statement: After s.save(t), every entry (h -> m) written for a node satisfies h == keccak256(m), and every non-embedded child hash in a saved node resolves to that child's encoding.
- Java: **diverges**: Holds for every non-empty node. The empty root is stored under EMPTY_HASH = keccak256(0x80) with value 0x40 (TRIE-HASH-02), so h != keccak256(m) for that entry. (`co/rsk/trie/TrieStoreImpl.java:99`, `co/rsk/trie/TrieStoreImpl.java:141`)
- Reproducer: Sanity run: TrieStoreImpl(HashMapDB).save(new Trie(store)); db[56e81f...b421] == 40.
- Notes: Minor: retrieve(EMPTY_HASH) still returns the empty trie.

### TRIE-STORE-06: Epoch migration keeps live nodes (requirement, Java diverges)

- RSKIP: `IPs/RSKIP64.md:47-53` (Epoch migration process)
- Quote:

  > **Epoch migration process**. Given two consecutive epochs `A`, `B`, their frontier blocks `a`, `b`, and databases `d(A)`, `d(B)`, a new epoch `C` will be created, with frontier block `c` and database `d(c)`. Then
  > 
  > 1. `d(C)` is considered the new database for new updates.
  > 1. We take `s` the `state` at `b.`
  > 1. We travel `s` searching the trie for all entries in `d(A)` but not in `d(B)`.
  > 1. For each entry in `d(A)` and not in `d(B)`, the entry is copied into `d(B).` Children of copied nodes could be copied automatically without checking existence in d(B).
  > 1. `d(A)` is deleted (atomically)

- Statement: After MultiTrieStore.collect(r), every node and long value reachable from root r is still retrievable (entries only in the oldest epoch are copied to the next one before it is disposed).
- Java: **diverges**: collect retrieves r (marked saved by retrieve, :94) and calls save on it; TrieStoreImpl.save returns at once for saved nodes and only walks loaded children, so nothing is copied. (`co/rsk/trie/MultiTrieStore.java:137-150`, `co/rsk/trie/MultiTrieStore.java:94`, `co/rsk/trie/TrieStoreImpl.java:93-95`, `co/rsk/trie/TrieStoreImpl.java:108-118`)
- Reproducer: Sanity run: MultiTrieStore(0, 3, TrieStoreImpl(HashMapDB) factory); save a 2-key trie; collect(root) three times; retrieve(root) is present after collects 1 and 2 and absent after collect 3.

## Stage 2 (follow-up)

| ID | Kind | Statement | Citation | Java reading |
| --- | --- | --- | --- | --- |
| TRIE-PROOF-01 | derived | **getNodes returns the path to the root.** For reachable t and key k present in t, t.getNodes(k) lists the node holding k first and the root last, each node referenced (by hash or embedding) by the next; it returns null if k is absent. | `IPs/RSKIP24.md:56` | **conforms** (`co/rsk/trie/Trie.java:1169-1217`, `co/rsk/rpc/modules/rsk/RskModuleImpl.java:126-130`, `co/rsk/core/bc/BlockHashesHelper.java:40-74`) |
| TRIE-PROOF-02 | derived | **Membership proofs verify against the root.** Recomputing hashes along toMessage() of the getNodes(k) path reproduces t.getHash(); changing any byte of any path node (or the value) changes the result, assuming keccak256 is collision resistant. | `IPs/RSKIP24.md:54; 56` | **unclear**: rskj has no in-tree verifier for Unitrie proofs; only the path is exported. (`co/rsk/trie/Trie.java:1169-1217`) |
| TRIE-PROOF-03 | derived | **treeSize supports verifiable chunked sync.** A chunk of the serialized tree identified by (offset, size) can be verified against the root using treeSize values, without the other chunks. | `IPs/RSKIP107.md:93` | **unclear**: No implementation of this use found. (`co/rsk/trie/Trie.java:1001-1011`) |

RSKIP92 (Adopted, "Merkle Proof serialization") is about the Bitcoin merged-mining coinbase proof, not Unitrie proofs; it is not used here.
