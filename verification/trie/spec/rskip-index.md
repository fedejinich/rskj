# RSKIP index for the trie spec

RSKIPs clone: `/Users/void_rsk/.treehouse/firstmate-ff549e/6/firstmate/projects/rskips-fork` at
`c578f4e932854830bb81f3de209eeeda6f7724b1` (`git -C <clone> rev-parse HEAD`). 224 files under `IPs/`.
There is no `IPs/RSKIP126.md`.

How the candidates were found (bodies, not only titles):

```sh
grep -liE 'unitrie|trie node|shared ?path|shared ?prefix|embedded node|long value|valueHash|value hash|childrenSize|children size|treeSize|varint|trie key|storage key|account key|code key' IPs/*.md
grep -liE '\btrie\b' IPs/*.md
grep -nE 'RSKIP-?0?(16|24|107|108|109|112|113|126|64)\b' IPs/*.md
```

Status is the `status:` front-matter field. "rskj" is the activation evidence at rskj `ecef55ddf`
(`reference.conf`, `ConsensusRule.java`); "none" means no ConsensusRule and no reference.conf entry.

## Read in full

| RSKIP | Title | Status | rskj | Relevance |
| --- | --- | --- | --- | --- |
| 16 | Combined State Tree | Draft | none | **In scope.** Unitrie layout: namespace byte 0x00, field selectors 0x00 storage / 0x80 code (`:49-53`). Its full-hash addresses (`:65`) are replaced by RSKIP108. |
| 24 | New Binary Trie | Adopted (parts deprecated, `:29`) | none | **In scope (goals only).** Hash map, authenticated structure, short proofs, insertion-order independence (`:50-58`), immutability (`:74`), lazy hashes (`:76`), disk placeholders (`:78`). CCR block verification is out (deprecated). |
| 64 | Garbage Collector for State Pruning | Draft | used only if `blockchain.gc.enabled` (default false, `reference.conf:110-114`) | **In scope for STORE only.** Epoch databases, read order, migration (`:36-53`) -> `MultiTrieStore`. |
| 107 | Smaller Unitrie Nodes for Higher Scalability | Draft | no rule of its own; hash is consensus from RSKIP126 (`reference.conf:28`, wasabi100) | **In scope, core.** Node format, flags, shared-prefix compression, VarInt, embedding, long values, treeSize (`:48-120`); old format in Motivation (`:32-44`). |
| 108 | More Efficient Unitrie Key Mapping | Draft | none (TrieKeyMapper is unconditional) | **In scope.** Key mapping table and trimming (`:55-66`). |
| 109 | Lower Storage Gas Costs for Shorter Keys | Draft | none | Out of scope: gas schedule only. |
| 112 | Unitrie Node identifiers | Draft | none | **Informational (TRIE-KEY-10).** Type-byte prefix on values (`:35-42`); not implemented in rskj. |
| 113 | Unified Cache-Oriented Storage Rent for the Unitrie | Draft | none | Out of scope: rent; `lastRentPaidTime` node field (`:40`) not implemented. |
| 144 | Parallel Transaction Execution for Unitrie | Draft | `rskip144 = reed810` (`reference.conf:35`; mainnet `reed810 = -1`) | Out of scope: transaction scheduling; recursive-delete connectivity (`:90`) is an integration concern, not trie encoding. |
| 173 | Chunk-Based Code Merkleization using the Unitrie | Draft | none | Out of scope: not implemented. Would change the long-value threshold to 64 bytes (`:85`); noted in TRIE-VAL-01. |
| 239 | Reprice Trie Read Opcodes | Draft | none | Out of scope: gas only. |
| 240 | Implement Storage Rent in RSK | Draft | none | **Cited, rent itself out of scope.** Node version numbering 0 = Orchid, 1 = RSKIP107, 2 = rent (`:53`) -> TRIE-NODE-02, TRIE-SER-04; ">32 bytes stored separately" (`:85`) -> TRIE-VAL-01, TRIE-STORE-04; SELFDESTRUCT deletes storage (`:153`) -> TRIE-OPS-09. |

## Read in the matching passages only

| RSKIP | Title | Status | Relevance |
| --- | --- | --- | --- |
| 242 | Proxy code Incentive | Draft | **Cited.** States the embedding threshold as 44 bytes (`:27`, `:56`) -> TRIE-EMB-03. Gas rule out of scope. |
| 244 | Variable Storage Costs | Draft | **Cited.** "storage cells of 44 bytes or less are embedded" (`:33`, `:35`, `:112`) -> TRIE-EMB-03. Gas rule out of scope. |
| 92 | Merkle Proof serialization | Adopted | Out of scope: Bitcoin merged-mining coinbase proof (`:38-75`), not Unitrie proofs. |
| 243 | Intra-transaction Gas Refunds | Draft | Out of scope: gas refunds. |
| 25 | Memory caches | Draft | Out of scope: node cache design (`:56`), no format rule. |
| 01 | Distributed Memory | Draft | Out of scope: foreign-storage trie proposal. |
| 07, 17, 21, 27, 52, 61 | Storage rent / hibernation variants | Rejected or Draft | Out of scope: rent and hibernation; no Stage 1 trie rule. |
| 18, 31 | Hibernation wakeup / compression | Draft | Out of scope: hibernation. |
| 30 | Code Pagination | Draft | Out of scope: code paging overhead estimate only. |
| 32 | Double-Hashed Addresses | Draft | Out of scope: address format; bit-order reversal proposal (`:82`) not implemented. |
| 19, 39 | Address formats / multi-key | Draft | Out of scope: reference RSKIP16 address type byte only. |
| 45 | New Event Tree and Extended LOG | Adopted | Out of scope: events trie root in header. |
| 53 | LTCP | Draft | Out of scope: uses RSKIP16 field selectors 0x01/0x02 (`:115`, `:153`), not implemented. |
| 55, 62, 70, 102, 131, 138, 145, 149, 281 | Various (payments, block propagation, default data, fee bumping, CREATE2, multisig, tx format, transfers, rollup calldata) | Draft | Out of scope: mention the (Uni)trie only as context. |
| 14, 15, 85, 140 | REMASC / EXTCODEHASH | Rejected / Adopted | Out of scope: mention state or tx trie only as context. |
| 41, 377, 387, 419, 428 | Bridge / powpeg | Draft / Adopted | Out of scope: matched "VarInt" or "storage key" in bridge contexts only. |
| 518 | Network Upgrade - Reed | Draft | Out of scope: lists RSKIP144 (testnet-only). |

## Not present

- RSKIP126: referenced by rskj (`ConsensusRule.java:41`, `reference.conf:28`) as the switch from Orchid to RSKIP107
  hashes for state, transaction and receipt roots (`StateRootHandler.java:41-52`, `BlockHashesHelper.java:22-29,76-83`),
  but there is no `IPs/RSKIP126.md` in the clone.
