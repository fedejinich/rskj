import RskjTrie.Keccak
/-! Keccak-256 test vectors (run by `scripts/check.sh`; evaluation, not proof). -/
open RskjTrie

-- keccak256("")
#guard toHex (Keccak.keccak256 []) == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
-- keccak256(0x80) = keccak256(RLP("")) = the empty trie hash
#guard toHex (Keccak.keccak256 [0x80]) == "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
-- keccak256(32 zero bytes)
#guard toHex (Keccak.keccak256 (List.replicate 32 0)) == "290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563"
-- keccak256("abc")
#guard toHex (Keccak.keccak256 [0x61, 0x62, 0x63]) == "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"
