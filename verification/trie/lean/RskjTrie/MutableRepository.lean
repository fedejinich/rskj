import RskjTrie.Ops
import RskjTrie.TrieKeyMapper
/-!
# `org.ethereum.db.MutableRepository` — only the storage-root placeholder write

`setupContract(addr)` (MutableRepository.java:105-109) writes `ONE_BYTE_ARRAY = {0x01}`
(MutableRepository.java:56) at `getAccountStoragePrefixKey(addr)` through
`internalPut` (MutableRepository.java:416-419) → `MutableTrieImpl.put` (MutableTrieImpl.java:58-60)
→ `Trie.put`. (`MutableTrieCache`, used while tracking, buffers the same `put` and commits it to
the underlying `MutableTrieImpl`.)
-/
namespace RskjTrie.MutableRepository

/-- `ONE_BYTE_ARRAY` — MutableRepository.java:56. -/
def ONE_BYTE_ARRAY : Bytes := [0x01]

/-- `MutableRepository.setupContract(RskAddress)` — MutableRepository.java:105-109. -/
def setupContract (env : Env) (t : Trie) (addr : Bytes) : Except Err Trie :=
  t.put env (TrieKeyMapper.getAccountStoragePrefixKey env.H addr) (some ONE_BYTE_ARRAY)

end RskjTrie.MutableRepository
