use crate::core_trie::Unitrie;
use crate::next::hash_cache::HashCache;
use crate::next::node_arena::NodeArena;
use crate::next::persistence::IncrementalPersistence;
use crate::node_ref::HASH_SIZE;
use crate::store_adapter::RawStoreAdapter;

#[derive(Debug, Default, Clone)]
pub struct NextUnitrie {
    inner: Unitrie,
    node_arena: NodeArena,
    hash_cache: HashCache,
    persistence: IncrementalPersistence,
}

impl NextUnitrie {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn from_persisted_root<T: RawStoreAdapter>(
        root_hash: &[u8],
        store: &mut T,
    ) -> Result<Self, String> {
        let inner = Unitrie::from_persisted_root(root_hash, store)?;
        let mut this = Self {
            inner,
            ..Self::default()
        };
        this.hash_cache.update_root(this.inner.current_root_hash());
        Ok(this)
    }

    pub fn get(&self, key: &[u8]) -> Option<Vec<u8>> {
        self.inner.get(key)
    }

    pub fn get_ref(&self, key: &[u8]) -> Option<&[u8]> {
        self.inner.get_ref(key)
    }

    pub fn put(&mut self, key: Vec<u8>, value: Vec<u8>) {
        self.node_arena.mark_dirty_key(&key);
        self.hash_cache.invalidate();
        self.inner.put(key, value);
    }

    pub fn delete(&mut self, key: &[u8]) {
        self.node_arena.mark_dirty_key(key);
        self.hash_cache.invalidate();
        self.inner.delete(key);
    }

    pub fn delete_recursive(&mut self, prefix: &[u8]) {
        self.node_arena.mark_dirty_key(prefix);
        self.hash_cache.invalidate();
        self.inner.delete_recursive(prefix);
    }

    pub fn get_value_length(&self, key: &[u8]) -> Option<usize> {
        self.inner.get_value_length(key)
    }

    pub fn get_value_hash(&self, key: &[u8]) -> Option<[u8; HASH_SIZE]> {
        self.inner.get_value_hash(key)
    }

    pub fn collect_keys(&self, byte_size: usize) -> Vec<Vec<u8>> {
        self.inner.collect_keys(byte_size)
    }

    pub fn get_storage_keys(&self, account_address: &[u8]) -> Vec<Vec<u8>> {
        self.inner.get_storage_keys(account_address)
    }

    pub fn root_hash(&mut self) -> [u8; HASH_SIZE] {
        if let Some(cached) = self.hash_cache.root_hash() {
            return cached;
        }

        let root = self.inner.root_hash();
        self.hash_cache.update_root(root);
        root
    }

    pub fn current_root_hash(&mut self) -> [u8; HASH_SIZE] {
        self.root_hash()
    }

    pub fn save_to_store<T: RawStoreAdapter>(&mut self, store: &mut T) {
        self.persistence
            .save(&mut self.inner, store, self.node_arena.dirty_count());
        self.node_arena.clear_dirty();
        self.hash_cache.update_root(self.inner.current_root_hash());
    }
}
