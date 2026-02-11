use crate::core_trie::Unitrie;
use crate::next::core_trie::NextUnitrie;
use crate::store_adapter::RawStoreAdapter;
use dashmap::DashMap;
use jni::objects::{JByteArray, JClass, JObject, JString, JValue};
use jni::sys::{jbyteArray, jint, jlong, jlongArray, jobjectArray};
use jni::JNIEnv;
use once_cell::sync::Lazy;
use std::sync::atomic::{AtomicI64, Ordering};

static NEXT_HANDLE: AtomicI64 = AtomicI64::new(1);
static TRIES: Lazy<DashMap<i64, TrieHandle>> = Lazy::new(DashMap::new);

#[derive(Debug, Clone, Copy)]
enum RuntimeImplementation {
    LegacyV1,
    Next,
}

impl RuntimeImplementation {
    fn from_config(value: &str) -> Result<Self, String> {
        let normalized = value.trim().to_ascii_lowercase();
        match normalized.as_str() {
            "legacy-v1" => Ok(Self::LegacyV1),
            "next" => Ok(Self::Next),
            _ => Err(format!(
                "unsupported unitrie implementation '{value}'. expected one of: legacy-v1, next"
            )),
        }
    }
}

#[derive(Debug, Default, Clone)]
struct PerfCounters {
    serialized_nodes: u64,
    hashed_nodes: u64,
    persisted_nodes: u64,
    persisted_values: u64,
    cache_hits: u64,
    cache_misses: u64,
    jni_calls: u64,
}

impl PerfCounters {
    fn as_long_vec(&self) -> Vec<jlong> {
        vec![
            self.serialized_nodes as jlong,
            self.hashed_nodes as jlong,
            self.persisted_nodes as jlong,
            self.persisted_values as jlong,
            self.cache_hits as jlong,
            self.cache_misses as jlong,
            self.jni_calls as jlong,
        ]
    }
}

#[derive(Debug)]
enum TrieRuntime {
    Legacy(Unitrie),
    Next(NextUnitrie),
}

impl TrieRuntime {
    fn new(implementation: RuntimeImplementation) -> Self {
        match implementation {
            RuntimeImplementation::LegacyV1 => Self::Legacy(Unitrie::new()),
            RuntimeImplementation::Next => Self::Next(NextUnitrie::new()),
        }
    }

    fn from_persisted_root<T: RawStoreAdapter>(
        implementation: RuntimeImplementation,
        root_hash: &[u8],
        store: &mut T,
    ) -> Result<Self, String> {
        match implementation {
            RuntimeImplementation::LegacyV1 => {
                Unitrie::from_persisted_root(root_hash, store).map(Self::Legacy)
            }
            RuntimeImplementation::Next => {
                NextUnitrie::from_persisted_root(root_hash, store).map(Self::Next)
            }
        }
    }

    fn get(&self, key: &[u8]) -> Option<Vec<u8>> {
        match self {
            Self::Legacy(trie) => trie.get(key),
            Self::Next(trie) => trie.get(key),
        }
    }

    fn put(&mut self, key: Vec<u8>, value: Vec<u8>) {
        match self {
            Self::Legacy(trie) => trie.put(key, value),
            Self::Next(trie) => trie.put(key, value),
        }
    }

    fn delete(&mut self, key: &[u8]) {
        match self {
            Self::Legacy(trie) => trie.delete(key),
            Self::Next(trie) => trie.delete(key),
        }
    }

    fn delete_recursive(&mut self, key: &[u8]) {
        match self {
            Self::Legacy(trie) => trie.delete_recursive(key),
            Self::Next(trie) => trie.delete_recursive(key),
        }
    }

    fn get_value_length(&self, key: &[u8]) -> Option<usize> {
        match self {
            Self::Legacy(trie) => trie.get_value_length(key),
            Self::Next(trie) => trie.get_value_length(key),
        }
    }

    fn get_value_hash(&self, key: &[u8]) -> Option<[u8; 32]> {
        match self {
            Self::Legacy(trie) => trie.get_value_hash(key),
            Self::Next(trie) => trie.get_value_hash(key),
        }
    }

    fn collect_keys(&self, size: usize) -> Vec<Vec<u8>> {
        match self {
            Self::Legacy(trie) => trie.collect_keys(size),
            Self::Next(trie) => trie.collect_keys(size),
        }
    }

    fn get_storage_keys(&self, account_address: &[u8]) -> Vec<Vec<u8>> {
        match self {
            Self::Legacy(trie) => trie.get_storage_keys(account_address),
            Self::Next(trie) => trie.get_storage_keys(account_address),
        }
    }

    fn root_hash(&mut self) -> [u8; 32] {
        match self {
            Self::Legacy(trie) => trie.root_hash(),
            Self::Next(trie) => trie.root_hash(),
        }
    }

    fn current_root_hash(&mut self) -> [u8; 32] {
        match self {
            Self::Legacy(trie) => trie.current_root_hash(),
            Self::Next(trie) => trie.current_root_hash(),
        }
    }

    fn save_to_store<T: RawStoreAdapter>(&mut self, store: &mut T) {
        match self {
            Self::Legacy(trie) => trie.save_to_store(store),
            Self::Next(trie) => trie.save_to_store(store),
        }
    }
}

#[derive(Debug)]
struct TrieHandle {
    runtime: TrieRuntime,
    counters: PerfCounters,
}

impl TrieHandle {
    fn new(runtime: TrieRuntime) -> Self {
        Self {
            runtime,
            counters: PerfCounters::default(),
        }
    }
}

#[derive(Debug, Default, Clone, Copy)]
struct StoreStats {
    load_hits: u64,
    load_misses: u64,
    saved_nodes: u64,
    saved_values: u64,
}

struct CountingRawStoreAdapter<'a, T: RawStoreAdapter> {
    inner: &'a mut T,
    stats: StoreStats,
}

impl<'a, T: RawStoreAdapter> CountingRawStoreAdapter<'a, T> {
    fn new(inner: &'a mut T) -> Self {
        Self {
            inner,
            stats: StoreStats::default(),
        }
    }
}

impl<'a, T: RawStoreAdapter> RawStoreAdapter for CountingRawStoreAdapter<'a, T> {
    fn load_raw_node(&mut self, hash: &[u8]) -> Option<Vec<u8>> {
        let value = self.inner.load_raw_node(hash);
        if value.is_some() {
            self.stats.load_hits = self.stats.load_hits.saturating_add(1);
        } else {
            self.stats.load_misses = self.stats.load_misses.saturating_add(1);
        }
        value
    }

    fn load_raw_value(&mut self, hash: &[u8]) -> Option<Vec<u8>> {
        let value = self.inner.load_raw_value(hash);
        if value.is_some() {
            self.stats.load_hits = self.stats.load_hits.saturating_add(1);
        } else {
            self.stats.load_misses = self.stats.load_misses.saturating_add(1);
        }
        value
    }

    fn save_raw_node(&mut self, hash: &[u8], serialized_node: &[u8]) {
        self.stats.saved_nodes = self.stats.saved_nodes.saturating_add(1);
        self.inner.save_raw_node(hash, serialized_node);
    }

    fn save_raw_value(&mut self, hash: &[u8], value: &[u8]) {
        self.stats.saved_values = self.stats.saved_values.saturating_add(1);
        self.inner.save_raw_value(hash, value);
    }
}

fn throw_illegal_state(env: &mut JNIEnv, message: impl AsRef<str>) {
    let _ = env.throw_new("java/lang/IllegalStateException", message.as_ref());
}

fn throw_illegal_argument(env: &mut JNIEnv, message: impl AsRef<str>) {
    let _ = env.throw_new("java/lang/IllegalArgumentException", message.as_ref());
}

fn convert_required_array(
    env: &mut JNIEnv,
    value: JByteArray,
    param_name: &str,
) -> Result<Vec<u8>, ()> {
    if value.is_null() {
        throw_illegal_argument(env, format!("{param_name} must not be null"));
        return Err(());
    }

    env.convert_byte_array(value).map_err(|err| {
        throw_illegal_argument(env, format!("invalid {param_name}: {err}"));
    })
}

fn convert_required_string(env: &mut JNIEnv, value: JString, param_name: &str) -> Result<String, ()> {
    if value.is_null() {
        throw_illegal_argument(env, format!("{param_name} must not be null"));
        return Err(());
    }

    env.get_string(&value)
        .map_err(|err| {
            throw_illegal_argument(env, format!("invalid {param_name}: {err}"));
        })
        .map(|v| v.into())
}

fn parse_implementation(env: &mut JNIEnv, value: JString) -> Result<RuntimeImplementation, ()> {
    let configured = convert_required_string(env, value, "implementation")?;
    RuntimeImplementation::from_config(&configured).map_err(|err| {
        throw_illegal_argument(env, err);
    })
}

fn to_byte_array(env: &mut JNIEnv, bytes: &[u8], error_context: &str) -> Option<jbyteArray> {
    match env.byte_array_from_slice(bytes) {
        Ok(array) => Some(array.into_raw()),
        Err(err) => {
            throw_illegal_state(env, format!("could not return {error_context}: {err}"));
            None
        }
    }
}

fn to_long_array(env: &mut JNIEnv, values: &[jlong], error_context: &str) -> Option<jlongArray> {
    let array = match env.new_long_array(values.len() as jint) {
        Ok(array) => array,
        Err(err) => {
            throw_illegal_state(env, format!("could not allocate {error_context}: {err}"));
            return None;
        }
    };

    if let Err(err) = env.set_long_array_region(&array, 0, values) {
        throw_illegal_state(env, format!("could not write {error_context}: {err}"));
        return None;
    }

    Some(array.into_raw())
}

fn with_trie_mut<T>(handle: jlong, f: impl FnOnce(&mut TrieHandle) -> T) -> Result<T, String> {
    let mut trie_handle = match TRIES.get_mut(&handle) {
        Some(trie_handle) => trie_handle,
        None => {
            return Err(format!("unknown trie handle {handle}"));
        }
    };

    trie_handle.counters.jni_calls = trie_handle.counters.jni_calls.saturating_add(1);
    Ok(f(&mut trie_handle))
}

struct JavaRawStoreAdapter<'a, 'b> {
    env: &'a mut JNIEnv<'b>,
    adapter: JObject<'b>,
}

impl<'a, 'b> JavaRawStoreAdapter<'a, 'b> {
    fn new(env: &'a mut JNIEnv<'b>, adapter: JObject<'b>) -> Result<Self, ()> {
        if adapter.is_null() {
            throw_illegal_argument(env, "storeAdapter must not be null");
            return Err(());
        }

        Ok(Self { env, adapter })
    }
}

impl<'a, 'b> RawStoreAdapter for JavaRawStoreAdapter<'a, 'b> {
    fn load_raw_node(&mut self, hash: &[u8]) -> Option<Vec<u8>> {
        let hash_array = match self.env.byte_array_from_slice(hash) {
            Ok(array) => array,
            Err(_) => return None,
        };
        let hash_object = JObject::from(hash_array);

        let result = self
            .env
            .call_method(
                &self.adapter,
                "loadRawNode",
                "([B)[B",
                &[JValue::Object(&hash_object)],
            )
            .ok()?;

        let payload_object = result.l().ok()?;
        if payload_object.is_null() {
            return None;
        }

        let payload_array = JByteArray::from(payload_object);
        self.env.convert_byte_array(payload_array).ok()
    }

    fn save_raw_node(&mut self, hash: &[u8], serialized_node: &[u8]) {
        let hash_array = match self.env.byte_array_from_slice(hash) {
            Ok(array) => array,
            Err(_) => return,
        };
        let node_array = match self.env.byte_array_from_slice(serialized_node) {
            Ok(array) => array,
            Err(_) => return,
        };
        let hash_object = JObject::from(hash_array);
        let node_object = JObject::from(node_array);

        let _ = self.env.call_method(
            &self.adapter,
            "saveRawNode",
            "([B[B)V",
            &[JValue::Object(&hash_object), JValue::Object(&node_object)],
        );
    }

    fn save_raw_value(&mut self, hash: &[u8], value: &[u8]) {
        let hash_array = match self.env.byte_array_from_slice(hash) {
            Ok(array) => array,
            Err(_) => return,
        };
        let value_array = match self.env.byte_array_from_slice(value) {
            Ok(array) => array,
            Err(_) => return,
        };
        let hash_object = JObject::from(hash_array);
        let value_object = JObject::from(value_array);

        let _ = self.env.call_method(
            &self.adapter,
            "saveRawValue",
            "([B[B)V",
            &[JValue::Object(&hash_object), JValue::Object(&value_object)],
        );
    }

    fn load_raw_value(&mut self, hash: &[u8]) -> Option<Vec<u8>> {
        self.load_raw_node(hash)
    }
}

fn bytes_vec_to_jobject_array(env: &mut JNIEnv, values: Vec<Vec<u8>>) -> Option<jobjectArray> {
    let byte_array_class = match env.find_class("[B") {
        Ok(class) => class,
        Err(err) => {
            throw_illegal_state(env, format!("could not resolve byte[] class: {err}"));
            return None;
        }
    };

    let array = match env.new_object_array(values.len() as i32, byte_array_class, JObject::null()) {
        Ok(array) => array,
        Err(err) => {
            throw_illegal_state(env, format!("could not allocate key array: {err}"));
            return None;
        }
    };

    for (index, value) in values.into_iter().enumerate() {
        let item = match env.byte_array_from_slice(&value) {
            Ok(item) => item,
            Err(err) => {
                throw_illegal_state(env, format!("could not allocate key array element: {err}"));
                return None;
            }
        };

        if let Err(err) = env.set_object_array_element(&array, index as i32, JObject::from(item)) {
            throw_illegal_state(env, format!("could not set key array element: {err}"));
            return None;
        }
    }

    Some(array.into_raw())
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeCreateTrie(
    mut env: JNIEnv,
    _class: JClass,
    implementation: JString,
) -> jlong {
    let implementation = match parse_implementation(&mut env, implementation) {
        Ok(implementation) => implementation,
        Err(_) => return 0,
    };

    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    TRIES.insert(handle, TrieHandle::new(TrieRuntime::new(implementation)));
    handle
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeCreateTrieFromRoot<'a>(
    mut env: JNIEnv<'a>,
    _class: JClass<'a>,
    root_hash: JByteArray<'a>,
    store_adapter: JObject<'a>,
    implementation: JString<'a>,
) -> jlong {
    let implementation = match parse_implementation(&mut env, implementation) {
        Ok(implementation) => implementation,
        Err(_) => return 0,
    };

    let root_hash = match convert_required_array(&mut env, root_hash, "rootHash") {
        Ok(root_hash) => root_hash,
        Err(_) => return 0,
    };

    let mut adapter = match JavaRawStoreAdapter::new(&mut env, store_adapter) {
        Ok(adapter) => adapter,
        Err(_) => return 0,
    };

    let mut counting_adapter = CountingRawStoreAdapter::new(&mut adapter);
    let runtime = match TrieRuntime::from_persisted_root(implementation, &root_hash, &mut counting_adapter) {
        Ok(trie) => trie,
        Err(err) => {
            throw_illegal_argument(
                &mut env,
                format!("could not create trie from persisted root: {err}"),
            );
            return 0;
        }
    };

    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    let mut trie_handle = TrieHandle::new(runtime);
    trie_handle.counters.cache_hits = trie_handle
        .counters
        .cache_hits
        .saturating_add(counting_adapter.stats.load_hits);
    trie_handle.counters.cache_misses = trie_handle
        .counters
        .cache_misses
        .saturating_add(counting_adapter.stats.load_misses);

    TRIES.insert(handle, trie_handle);
    handle
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeDestroyTrie(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    if handle == 0 {
        return;
    }

    TRIES.remove(&handle);
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeGet(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
    key: JByteArray,
) -> jbyteArray {
    let key = match convert_required_array(&mut env, key, "key") {
        Ok(key) => key,
        Err(_) => return std::ptr::null_mut(),
    };

    let value = match with_trie_mut(handle, |trie| trie.runtime.get(&key)) {
        Ok(value) => value,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            return std::ptr::null_mut();
        }
    };

    match value {
        Some(value) => to_byte_array(&mut env, &value, "value").unwrap_or(std::ptr::null_mut()),
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativePut(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
    key: JByteArray,
    value: JByteArray,
) {
    let key = match convert_required_array(&mut env, key, "key") {
        Ok(key) => key,
        Err(_) => return,
    };

    let value = if value.is_null() {
        None
    } else {
        match env.convert_byte_array(value) {
            Ok(value) => Some(value),
            Err(err) => {
                throw_illegal_argument(&mut env, format!("invalid value: {err}"));
                return;
            }
        }
    };

    if let Err(err) = with_trie_mut(handle, |trie| match value {
        Some(value) => trie.runtime.put(key, value),
        None => trie.runtime.delete(&key),
    }) {
        throw_illegal_argument(&mut env, err);
    }
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeDelete(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
    key: JByteArray,
) {
    let key = match convert_required_array(&mut env, key, "key") {
        Ok(key) => key,
        Err(_) => return,
    };

    if let Err(err) = with_trie_mut(handle, |trie| trie.runtime.delete(&key)) {
        throw_illegal_argument(&mut env, err);
    }
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeDeleteRecursive(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
    key: JByteArray,
) {
    let key = match convert_required_array(&mut env, key, "key") {
        Ok(key) => key,
        Err(_) => return,
    };

    if let Err(err) = with_trie_mut(handle, |trie| trie.runtime.delete_recursive(&key)) {
        throw_illegal_argument(&mut env, err);
    }
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeSave<'a>(
    mut env: JNIEnv<'a>,
    _class: JClass<'a>,
    handle: jlong,
    store_adapter: JObject<'a>,
) {
    let mut adapter = match JavaRawStoreAdapter::new(&mut env, store_adapter) {
        Ok(adapter) => adapter,
        Err(_) => return,
    };

    let mut counting_adapter = CountingRawStoreAdapter::new(&mut adapter);
    if let Err(err) = with_trie_mut(handle, |trie| {
        trie.runtime.save_to_store(&mut counting_adapter);

        let saved_nodes = counting_adapter.stats.saved_nodes;
        let saved_values = counting_adapter.stats.saved_values;

        trie.counters.persisted_nodes = trie.counters.persisted_nodes.saturating_add(saved_nodes);
        trie.counters.persisted_values = trie
            .counters
            .persisted_values
            .saturating_add(saved_values);

        trie.counters.serialized_nodes = trie
            .counters
            .serialized_nodes
            .saturating_add(saved_nodes);
        trie.counters.hashed_nodes = trie
            .counters
            .hashed_nodes
            .saturating_add(saved_nodes.saturating_add(saved_values));
    }) {
        throw_illegal_argument(&mut env, err);
    }
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeGetValueLength(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
    key: JByteArray,
) -> jint {
    let key = match convert_required_array(&mut env, key, "key") {
        Ok(key) => key,
        Err(_) => return -1,
    };

    match with_trie_mut(handle, |trie| trie.runtime.get_value_length(&key)) {
        Ok(Some(value_length)) => value_length as jint,
        Ok(None) => -1,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            -1
        }
    }
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeGetValueHash(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
    key: JByteArray,
) -> jbyteArray {
    let key = match convert_required_array(&mut env, key, "key") {
        Ok(key) => key,
        Err(_) => return std::ptr::null_mut(),
    };

    let value_hash = match with_trie_mut(handle, |trie| trie.runtime.get_value_hash(&key)) {
        Ok(value_hash) => value_hash,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            return std::ptr::null_mut();
        }
    };

    match value_hash {
        Some(value_hash) => {
            to_byte_array(&mut env, &value_hash, "value hash").unwrap_or(std::ptr::null_mut())
        }
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeCollectKeys(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
    size: jint,
) -> jobjectArray {
    let size = if size < 0 { 0 } else { size as usize };

    let keys = match with_trie_mut(handle, |trie| trie.runtime.collect_keys(size)) {
        Ok(keys) => keys,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            return std::ptr::null_mut();
        }
    };

    bytes_vec_to_jobject_array(&mut env, keys).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeGetStorageKeys(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
    account_address: JByteArray,
) -> jobjectArray {
    let account_address = match convert_required_array(&mut env, account_address, "accountAddress") {
        Ok(account_address) => account_address,
        Err(_) => return std::ptr::null_mut(),
    };

    let keys = match with_trie_mut(handle, |trie| {
        trie.runtime.get_storage_keys(&account_address)
    }) {
        Ok(keys) => keys,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            return std::ptr::null_mut();
        }
    };

    bytes_vec_to_jobject_array(&mut env, keys).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeRootHash(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jbyteArray {
    let root_hash = match with_trie_mut(handle, |trie| trie.runtime.root_hash()) {
        Ok(root_hash) => root_hash,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            return std::ptr::null_mut();
        }
    };

    to_byte_array(&mut env, &root_hash, "root hash").unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeCurrentRootHash(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jbyteArray {
    let root_hash = match with_trie_mut(handle, |trie| trie.runtime.current_root_hash()) {
        Ok(root_hash) => root_hash,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            return std::ptr::null_mut();
        }
    };

    to_byte_array(&mut env, &root_hash, "current root hash").unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeGetPerfCounters(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jlongArray {
    let counters = match with_trie_mut(handle, |trie| trie.counters.as_long_vec()) {
        Ok(counters) => counters,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            return std::ptr::null_mut();
        }
    };

    to_long_array(&mut env, &counters, "perf counters").unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeResetPerfCounters(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    if let Err(err) = with_trie_mut(handle, |trie| {
        trie.counters = PerfCounters::default();
    }) {
        throw_illegal_argument(&mut env, err);
    }
}
