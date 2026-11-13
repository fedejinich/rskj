import RskjTrie.Basic
/-!
# `org.ethereum.db.TrieKeyMapper`

The address→key cache (`accountKeys`) is not modelled: it memoises a pure function and returns
copies.
-/
namespace RskjTrie.TrieKeyMapper

/-- `SECURE_KEY_SIZE` — TrieKeyMapper.java:38. -/
def SECURE_KEY_SIZE : Nat := 10
def DOMAIN_PREFIX : Bytes := [0x00]
def STORAGE_PREFIX : Bytes := [0x00]
def CODE_PREFIX : Bytes := [0x80]

/-- `secureKeyPrefix(byte[] key)` — TrieKeyMapper.java:77-79:
`Arrays.copyOfRange(keccak256(key), 0, 10)`. -/
def secureKeyPrefix (H : Bytes → Bytes) (key : Bytes) : Bytes := (H key).take SECURE_KEY_SIZE

/-- `mapRskAddressToKey(RskAddress)` — TrieKeyMapper.java:89-92. -/
def mapRskAddressToKey (H : Bytes → Bytes) (addr : Bytes) : Bytes :=
  DOMAIN_PREFIX ++ secureKeyPrefix H addr ++ addr

/-- `getAccountKey(RskAddress)` — TrieKeyMapper.java:48-59. -/
def getAccountKey (H : Bytes → Bytes) (addr : Bytes) : Bytes := mapRskAddressToKey H addr

/-- `getCodeKey(RskAddress)` — TrieKeyMapper.java:61-63. -/
def getCodeKey (H : Bytes → Bytes) (addr : Bytes) : Bytes := getAccountKey H addr ++ CODE_PREFIX

/-- `getAccountStoragePrefixKey(RskAddress)` — TrieKeyMapper.java:65-67. -/
def getAccountStoragePrefixKey (H : Bytes → Bytes) (addr : Bytes) : Bytes :=
  getAccountKey H addr ++ STORAGE_PREFIX

/-- `ByteUtil.firstNonZeroByte` + `ByteUtil.stripLeadingZeroes(byte[])` — ByteUtil.java:397-429
(all-zero input gives `ZERO_BYTE_ARRAY = {0}`). -/
def stripLeadingZeroes (data : Bytes) : Bytes :=
  match data.dropWhile (· == 0) with
  | [] => [0]
  | r => r

/-- `getAccountStorageKey(RskAddress, DataWord)` — TrieKeyMapper.java:69-75, with
`subkey = subkeyDW.getData()` (the 32 bytes of the word). -/
def getAccountStorageKey (H : Bytes → Bytes) (addr : Bytes) (subkey : Bytes) : Bytes :=
  let secureKeyPrefix := secureKeyPrefix H subkey
  let storageKey := secureKeyPrefix ++ stripLeadingZeroes subkey
  getAccountStoragePrefixKey H addr ++ storageKey

/-- `DataWord.valueOf(byte[] data)` — DataWord.java:566-585: empty → zero; more than 32 bytes →
`IllegalArgumentException`; else left-padded with zeros to 32 bytes. -/
def dataWordValueOf (data : Bytes) : Except Err Bytes :=
  if data.length = 0 then .ok (List.replicate 32 0)
  else if data.length > 32 then .error "IllegalArgumentException: A DataWord must be 32 bytes long"
  else .ok (List.replicate (32 - data.length) 0 ++ data)

/-- `new RskAddress(byte[])` — RskAddress.java:70-76: exactly 20 bytes. -/
def rskAddress (bytes : Bytes) : Except Err Bytes :=
  if bytes.length ≠ 20 then .error "InvalidRskAddressException" else .ok bytes

end RskjTrie.TrieKeyMapper
