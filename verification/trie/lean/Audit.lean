import RskjTrie
/-! Axiom audit: `scripts/check.sh` fails if any of these depends on `sorryAx`. -/
open RskjTrie

-- 1. PathEncoder
#print axioms PathEncoder.decode_encode
#print axioms PathEncoder.encode_length
#print axioms PathEncoder.encode_bitAt
#print axioms PathEncoder.encode_msb_first
#print axioms PathEncoder.encode_unused_bits_zero
#print axioms PathEncoder.decode_short
#print axioms TrieKeySlice.fromKey_eq
#print axioms TrieKeySlice.fromKey_injective
-- 2. VarInt
#print axioms VarInt.decode_encode
#print axioms VarInt.encode_length
#print axioms VarInt.sizeOf_eq_table
#print axioms VarInt.encode_eq
#print axioms readVarInt_encode
-- 3. Shared path length compression
#print axioms SharedPathSerializer.getPathBitsLength_prefix
#print axioms SharedPathSerializer.getPathBitsLength_large
#print axioms SharedPathSerializer.lsharedPrefix_length_one_iff
#print axioms SharedPathSerializer.lsharedPrefix_ranges
#print axioms SharedPathSerializer.calculateVarIntSize_eq
#print axioms SharedPathSerializer.serializedLength_eq
#print axioms SharedPathSerializer.deserialize_serializeInto
-- 4. Node serialization
#print axioms Trie.encOK
#print axioms Trie.toMessage_flags
#print axioms mkFlags_version
#print axioms Trie.fromMessage_toMessage
-- 5. put / get / delete
#print axioms Trie.get_eq_contents
#print axioms Trie.put_spec
#print axioms Trie.get_put
#print axioms Trie.get_delete
#print axioms Trie.delete_eq_put_empty
-- 6. Canonical shape
#print axioms Trie.WF_unique
#print axioms Trie.WF_same_encoding
#print axioms history_independent
-- 7. childrenSize
#print axioms Trie.childrenSize_from_scratch
#print axioms kidsSize_update_left
#print axioms kidsSize_update_right
-- 8. Hash
#print axioms Trie.getHash_nonempty
#print axioms Trie.getHash_empty
#print axioms Trie.empty_message_and_hash
#print axioms Trie.getHash_WF
-- 9. Store
#print axioms Trie.save_retrieve
#print axioms Trie.WF_PathsOK
#print axioms Trie.reparse_hashed_not_embeddable
-- 10. TrieKeyMapper
#print axioms TrieKeyMapper.accountKey_layout
#print axioms TrieKeyMapper.codeKey_layout
#print axioms TrieKeyMapper.storageKey_layout
#print axioms TrieKeyMapper.stripLeadingZeroes_zero
#print axioms TrieKeyMapper.address_recoverable
#print axioms TrieKeyMapper.storage_recoverable
