use crate::codec_rskip107::Rskip107Codec;
use crate::hash::{empty_trie_hash, keccak256};
use crate::node_ref::NodeReference;
use crate::store_adapter::RawStoreAdapter;
use std::collections::BTreeMap;

const LONG_VALUE_THRESHOLD: usize = 32;
const SNAPSHOT_VERSION: u8 = 1;

#[derive(Debug, Default, Clone)]
pub struct Unitrie {
    entries: BTreeMap<Vec<u8>, Vec<u8>>,
}

impl Unitrie {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn get(&self, key: &[u8]) -> Option<Vec<u8>> {
        self.entries.get(key).cloned()
    }

    pub fn put(&mut self, key: Vec<u8>, value: Vec<u8>) {
        self.entries.insert(key, value);
    }

    pub fn delete(&mut self, key: &[u8]) {
        self.entries.remove(key);
    }

    pub fn delete_recursive(&mut self, prefix: &[u8]) {
        let keys_to_delete: Vec<Vec<u8>> = self
            .entries
            .keys()
            .filter(|key| key.starts_with(prefix))
            .cloned()
            .collect();

        for key in keys_to_delete {
            self.entries.remove(&key);
        }
    }

    pub fn get_value_length(&self, key: &[u8]) -> Option<usize> {
        self.entries.get(key).map(Vec::len)
    }

    pub fn get_value_hash(&self, key: &[u8]) -> Option<[u8; 32]> {
        self.entries.get(key).map(|value| keccak256(value))
    }

    pub fn collect_keys(&self, size: usize) -> Vec<Vec<u8>> {
        self.entries.keys().take(size).cloned().collect()
    }

    pub fn get_storage_keys(&self, account_address: &[u8]) -> Vec<Vec<u8>> {
        self.entries
            .keys()
            .filter_map(|key| {
                if key.starts_with(account_address) && key.len() >= account_address.len() + 32 {
                    Some(key[key.len() - 32..].to_vec())
                } else {
                    None
                }
            })
            .collect()
    }

    pub fn root_hash(&self) -> [u8; 32] {
        if self.entries.is_empty() {
            return empty_trie_hash();
        }

        keccak256(&self.encoded_entries())
    }

    pub fn current_root_hash(&self) -> [u8; 32] {
        self.root_hash()
    }

    pub fn snapshot_payload(&self) -> Vec<u8> {
        let mut payload = Vec::new();
        payload.push(SNAPSHOT_VERSION);
        payload.extend_from_slice(&self.encoded_entries());
        payload
    }

    pub fn from_snapshot_payload(payload: &[u8]) -> Result<Self, String> {
        if payload.is_empty() {
            return Err("snapshot payload is empty".to_string());
        }

        if payload[0] != SNAPSHOT_VERSION {
            return Err(format!("unsupported snapshot version {}", payload[0]));
        }

        let entries = decode_entries(&payload[1..])?;
        Ok(Self { entries })
    }

    pub fn save_to_store<T: RawStoreAdapter>(&self, store: &mut T) {
        let root_hash = self.root_hash();
        let snapshot_payload = self.snapshot_payload();
        let serialized_node = Rskip107Codec::encode_node(&snapshot_payload);

        store.save_raw_node(&root_hash, &serialized_node);

        for value in self.entries.values() {
            if value.len() > LONG_VALUE_THRESHOLD {
                let value_hash = keccak256(value);
                store.save_raw_value(&value_hash, value);
            }
        }
    }

    pub fn children_size_estimate(&self) -> usize {
        // This mirrors the "child reference size" notion from Java in a simplified form.
        self.entries.len() * NodeReference::HASH_REFERENCE_SIZE
    }

    fn encoded_entries(&self) -> Vec<u8> {
        let mut payload = Vec::new();
        payload.extend_from_slice(&(self.entries.len() as u32).to_be_bytes());
        for (key, value) in &self.entries {
            append_length_prefixed(&mut payload, key);
            append_length_prefixed(&mut payload, value);
        }
        payload
    }
}

fn append_length_prefixed(output: &mut Vec<u8>, bytes: &[u8]) {
    output.extend_from_slice(&(bytes.len() as u32).to_be_bytes());
    output.extend_from_slice(bytes);
}

fn decode_entries(payload: &[u8]) -> Result<BTreeMap<Vec<u8>, Vec<u8>>, String> {
    if payload.len() < 4 {
        return Err("snapshot payload is truncated".to_string());
    }

    let mut cursor = 0usize;
    let total_entries = read_u32(payload, &mut cursor)? as usize;
    let mut entries = BTreeMap::new();

    for _ in 0..total_entries {
        let key = read_blob(payload, &mut cursor)?;
        let value = read_blob(payload, &mut cursor)?;
        entries.insert(key, value);
    }

    if cursor != payload.len() {
        return Err("snapshot payload has trailing bytes".to_string());
    }

    Ok(entries)
}

fn read_u32(payload: &[u8], cursor: &mut usize) -> Result<u32, String> {
    let end = *cursor + 4;
    if end > payload.len() {
        return Err("snapshot payload is truncated".to_string());
    }

    let mut bytes = [0u8; 4];
    bytes.copy_from_slice(&payload[*cursor..end]);
    *cursor = end;
    Ok(u32::from_be_bytes(bytes))
}

fn read_blob(payload: &[u8], cursor: &mut usize) -> Result<Vec<u8>, String> {
    let length = read_u32(payload, cursor)? as usize;
    let end = *cursor + length;
    if end > payload.len() {
        return Err("snapshot payload is truncated".to_string());
    }

    let value = payload[*cursor..end].to_vec();
    *cursor = end;
    Ok(value)
}

#[cfg(test)]
mod tests {
    use super::Unitrie;
    use crate::hash::empty_trie_hash;
    use crate::store_adapter::RawStoreAdapter;
    use std::collections::HashMap;

    #[derive(Default)]
    struct InMemoryStore {
        nodes: HashMap<Vec<u8>, Vec<u8>>,
        values: HashMap<Vec<u8>, Vec<u8>>,
    }

    impl RawStoreAdapter for InMemoryStore {
        fn save_raw_node(&mut self, hash: &[u8], serialized_node: &[u8]) {
            self.nodes.insert(hash.to_vec(), serialized_node.to_vec());
        }

        fn save_raw_value(&mut self, hash: &[u8], value: &[u8]) {
            self.values.insert(hash.to_vec(), value.to_vec());
        }
    }

    #[test]
    fn get_put_delete_round_trip() {
        let mut trie = Unitrie::new();
        trie.put(b"hello".to_vec(), b"world".to_vec());
        assert_eq!(trie.get(b"hello").as_deref(), Some(b"world".as_slice()));

        trie.delete(b"hello");
        assert!(trie.get(b"hello").is_none());
    }

    #[test]
    fn delete_recursive_removes_prefixed_keys_only() {
        let mut trie = Unitrie::new();
        trie.put(b"acct:1:aa".to_vec(), b"v1".to_vec());
        trie.put(b"acct:1:bb".to_vec(), b"v2".to_vec());
        trie.put(b"acct:2:aa".to_vec(), b"v3".to_vec());

        trie.delete_recursive(b"acct:1:");

        assert!(trie.get(b"acct:1:aa").is_none());
        assert!(trie.get(b"acct:1:bb").is_none());
        assert_eq!(trie.get(b"acct:2:aa").as_deref(), Some(b"v3".as_slice()));
    }

    #[test]
    fn empty_root_hash_matches_expected_semantics() {
        let trie = Unitrie::new();
        assert_eq!(trie.root_hash(), empty_trie_hash());
    }

    #[test]
    fn root_hash_is_stable_for_same_content() {
        let mut first = Unitrie::new();
        first.put(b"k1".to_vec(), b"v1".to_vec());
        first.put(b"k2".to_vec(), b"v2".to_vec());

        let mut second = Unitrie::new();
        second.put(b"k2".to_vec(), b"v2".to_vec());
        second.put(b"k1".to_vec(), b"v1".to_vec());

        assert_eq!(first.root_hash(), second.root_hash());
    }

    #[test]
    fn snapshot_round_trip() {
        let mut trie = Unitrie::new();
        trie.put(b"a".to_vec(), b"1".to_vec());
        trie.put(b"b".to_vec(), b"2".to_vec());

        let snapshot = trie.snapshot_payload();
        let loaded = Unitrie::from_snapshot_payload(&snapshot).expect("snapshot should decode");

        assert_eq!(loaded.get(b"a").as_deref(), Some(b"1".as_slice()));
        assert_eq!(loaded.get(b"b").as_deref(), Some(b"2".as_slice()));
        assert_eq!(loaded.root_hash(), trie.root_hash());
    }

    #[test]
    fn save_to_store_persists_node_and_long_values() {
        let mut trie = Unitrie::new();
        trie.put(b"short".to_vec(), vec![1; 32]);
        trie.put(b"long".to_vec(), vec![2; 40]);

        let mut store = InMemoryStore::default();
        trie.save_to_store(&mut store);

        assert_eq!(store.nodes.len(), 1);
        assert_eq!(store.values.len(), 1);
    }
}
