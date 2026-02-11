use crate::hash::{empty_trie_hash, keccak256};
use std::collections::BTreeMap;

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

    pub fn root_hash(&self) -> [u8; 32] {
        if self.entries.is_empty() {
            return empty_trie_hash();
        }

        // Deterministic canonical encoding over sorted entries.
        let mut payload = Vec::new();
        for (key, value) in &self.entries {
            append_length_prefixed(&mut payload, key);
            append_length_prefixed(&mut payload, value);
        }
        keccak256(&payload)
    }
}

fn append_length_prefixed(output: &mut Vec<u8>, bytes: &[u8]) {
    output.extend_from_slice(&(bytes.len() as u32).to_be_bytes());
    output.extend_from_slice(bytes);
}

#[cfg(test)]
mod tests {
    use super::Unitrie;
    use crate::hash::empty_trie_hash;

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
}
