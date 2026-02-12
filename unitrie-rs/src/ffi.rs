use crate::core_trie::Unitrie;
use crate::next::core_trie::NextUnitrie;
use crate::store_adapter::RawStoreAdapter;
use crate::varint;
use dashmap::DashMap;
use jni::objects::{JByteArray, JClass, JObject, JString, JValue};
use jni::sys::{jbyteArray, jint, jlong, jlongArray, jobjectArray};
use jni::JNIEnv;
use once_cell::sync::Lazy;
use std::sync::atomic::{AtomicI64, Ordering};
use std::time::Instant;

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
    ffi_decode_nanos: u64,
    ffi_encode_nanos: u64,
    core_runtime_nanos: u64,
    store_callback_nanos: u64,
    store_callback_calls: u64,
    jni_bytes_in: u64,
    jni_bytes_out: u64,
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
            self.ffi_decode_nanos as jlong,
            self.ffi_encode_nanos as jlong,
            self.core_runtime_nanos as jlong,
            self.store_callback_nanos as jlong,
            self.store_callback_calls as jlong,
            self.jni_bytes_in as jlong,
            self.jni_bytes_out as jlong,
        ]
    }

    fn add_decode_nanos(&mut self, elapsed_nanos: u64) {
        self.ffi_decode_nanos = self.ffi_decode_nanos.saturating_add(elapsed_nanos);
    }

    fn add_encode_nanos(&mut self, elapsed_nanos: u64) {
        self.ffi_encode_nanos = self.ffi_encode_nanos.saturating_add(elapsed_nanos);
    }

    fn add_core_nanos(&mut self, elapsed_nanos: u64) {
        self.core_runtime_nanos = self.core_runtime_nanos.saturating_add(elapsed_nanos);
    }

    fn add_store_callback_nanos(&mut self, elapsed_nanos: u64) {
        self.store_callback_nanos = self.store_callback_nanos.saturating_add(elapsed_nanos);
    }

    fn add_store_callback_calls(&mut self, calls: u64) {
        self.store_callback_calls = self.store_callback_calls.saturating_add(calls);
    }

    fn add_jni_bytes_in(&mut self, bytes: u64) {
        self.jni_bytes_in = self.jni_bytes_in.saturating_add(bytes);
    }

    fn add_jni_bytes_out(&mut self, bytes: u64) {
        self.jni_bytes_out = self.jni_bytes_out.saturating_add(bytes);
    }
}

#[derive(Debug)]
enum TrieRuntime {
    Legacy(Unitrie),
    Next(Box<NextUnitrie>),
}

impl TrieRuntime {
    fn new(implementation: RuntimeImplementation) -> Self {
        match implementation {
            RuntimeImplementation::LegacyV1 => Self::Legacy(Unitrie::new()),
            RuntimeImplementation::Next => Self::Next(Box::new(NextUnitrie::new())),
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
                NextUnitrie::from_persisted_root(root_hash, store)
                    .map(Box::new)
                    .map(Self::Next)
            }
        }
    }

    fn get_ref(&self, key: &[u8]) -> Option<&[u8]> {
        match self {
            Self::Legacy(trie) => trie.get_ref(key),
            Self::Next(trie) => trie.get_ref(key),
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

    fn get_storage_keys(&mut self, account_address: &[u8]) -> Vec<Vec<u8>> {
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
    callback_nanos: u64,
    callback_calls: u64,
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
        let callback_started = Instant::now();
        self.stats.callback_calls = self.stats.callback_calls.saturating_add(1);
        let value = self.inner.load_raw_node(hash);
        self.stats.callback_nanos = self
            .stats
            .callback_nanos
            .saturating_add(elapsed_nanos(callback_started));
        if value.is_some() {
            self.stats.load_hits = self.stats.load_hits.saturating_add(1);
        } else {
            self.stats.load_misses = self.stats.load_misses.saturating_add(1);
        }
        value
    }

    fn load_raw_value(&mut self, hash: &[u8]) -> Option<Vec<u8>> {
        let callback_started = Instant::now();
        self.stats.callback_calls = self.stats.callback_calls.saturating_add(1);
        let value = self.inner.load_raw_value(hash);
        self.stats.callback_nanos = self
            .stats
            .callback_nanos
            .saturating_add(elapsed_nanos(callback_started));
        if value.is_some() {
            self.stats.load_hits = self.stats.load_hits.saturating_add(1);
        } else {
            self.stats.load_misses = self.stats.load_misses.saturating_add(1);
        }
        value
    }

    fn save_raw_node(&mut self, hash: &[u8], serialized_node: &[u8]) {
        let callback_started = Instant::now();
        self.stats.callback_calls = self.stats.callback_calls.saturating_add(1);
        self.stats.saved_nodes = self.stats.saved_nodes.saturating_add(1);
        self.inner.save_raw_node(hash, serialized_node);
        self.stats.callback_nanos = self
            .stats
            .callback_nanos
            .saturating_add(elapsed_nanos(callback_started));
    }

    fn save_raw_value(&mut self, hash: &[u8], value: &[u8]) {
        let callback_started = Instant::now();
        self.stats.callback_calls = self.stats.callback_calls.saturating_add(1);
        self.stats.saved_values = self.stats.saved_values.saturating_add(1);
        self.inner.save_raw_value(hash, value);
        self.stats.callback_nanos = self
            .stats
            .callback_nanos
            .saturating_add(elapsed_nanos(callback_started));
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

fn elapsed_nanos(start: Instant) -> u64 {
    let elapsed = start.elapsed().as_nanos();
    if elapsed > u64::MAX as u128 {
        u64::MAX
    } else {
        elapsed as u64
    }
}

fn len_as_u64(value: usize) -> u64 {
    if value > u64::MAX as usize {
        u64::MAX
    } else {
        value as u64
    }
}

fn record_decode_metrics(handle: jlong, elapsed_nanos: u64, bytes_in: u64) {
    if let Some(mut trie_handle) = TRIES.get_mut(&handle) {
        trie_handle.counters.add_decode_nanos(elapsed_nanos);
        trie_handle.counters.add_jni_bytes_in(bytes_in);
    }
}

fn record_encode_metrics(handle: jlong, elapsed_nanos: u64, bytes_out: u64) {
    if let Some(mut trie_handle) = TRIES.get_mut(&handle) {
        trie_handle.counters.add_encode_nanos(elapsed_nanos);
        trie_handle.counters.add_jni_bytes_out(bytes_out);
    }
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
    callback_nanos: u64,
    callback_calls: u64,
}

impl<'a, 'b> JavaRawStoreAdapter<'a, 'b> {
    fn new(env: &'a mut JNIEnv<'b>, adapter: JObject<'b>) -> Result<Self, ()> {
        if adapter.is_null() {
            throw_illegal_argument(env, "storeAdapter must not be null");
            return Err(());
        }

        Ok(Self {
            env,
            adapter,
            callback_nanos: 0,
            callback_calls: 0,
        })
    }

    fn inner_stats_increment_call(&mut self) {
        self.callback_calls = self.callback_calls.saturating_add(1);
    }

    fn inner_stats_record_duration(&mut self, started: Instant) {
        self.callback_nanos = self.callback_nanos.saturating_add(elapsed_nanos(started));
    }
}

impl<'a, 'b> RawStoreAdapter for JavaRawStoreAdapter<'a, 'b> {
    fn load_raw_node(&mut self, hash: &[u8]) -> Option<Vec<u8>> {
        let callback_start = Instant::now();
        self.inner_stats_increment_call();
        let hash_array = match self.env.byte_array_from_slice(hash) {
            Ok(array) => array,
            Err(_) => {
                self.inner_stats_record_duration(callback_start);
                return None;
            }
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
            .ok();

        let payload_object = match result {
            Some(result) => result.l().ok(),
            None => None,
        };
        let payload_object = match payload_object {
            Some(payload_object) => payload_object,
            None => {
                self.inner_stats_record_duration(callback_start);
                return None;
            }
        };
        if payload_object.is_null() {
            self.inner_stats_record_duration(callback_start);
            return None;
        }

        let payload_array = JByteArray::from(payload_object);
        let output = self.env.convert_byte_array(payload_array).ok();
        self.inner_stats_record_duration(callback_start);
        output
    }

    fn save_raw_node(&mut self, hash: &[u8], serialized_node: &[u8]) {
        let callback_start = Instant::now();
        self.inner_stats_increment_call();
        let hash_array = match self.env.byte_array_from_slice(hash) {
            Ok(array) => array,
            Err(_) => {
                self.inner_stats_record_duration(callback_start);
                return;
            }
        };
        let node_array = match self.env.byte_array_from_slice(serialized_node) {
            Ok(array) => array,
            Err(_) => {
                self.inner_stats_record_duration(callback_start);
                return;
            }
        };
        let hash_object = JObject::from(hash_array);
        let node_object = JObject::from(node_array);

        let _ = self.env.call_method(
            &self.adapter,
            "saveRawNode",
            "([B[B)V",
            &[JValue::Object(&hash_object), JValue::Object(&node_object)],
        );
        self.inner_stats_record_duration(callback_start);
    }

    fn save_raw_value(&mut self, hash: &[u8], value: &[u8]) {
        let callback_start = Instant::now();
        self.inner_stats_increment_call();
        let hash_array = match self.env.byte_array_from_slice(hash) {
            Ok(array) => array,
            Err(_) => {
                self.inner_stats_record_duration(callback_start);
                return;
            }
        };
        let value_array = match self.env.byte_array_from_slice(value) {
            Ok(array) => array,
            Err(_) => {
                self.inner_stats_record_duration(callback_start);
                return;
            }
        };
        let hash_object = JObject::from(hash_array);
        let value_object = JObject::from(value_array);

        let _ = self.env.call_method(
            &self.adapter,
            "saveRawValue",
            "([B[B)V",
            &[JValue::Object(&hash_object), JValue::Object(&value_object)],
        );
        self.inner_stats_record_duration(callback_start);
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

fn encode_storage_keys_packed(values: &[Vec<u8>]) -> Vec<u8> {
    let mut payload_size = varint::size_of(values.len() as u64);
    for value in values {
        payload_size += varint::size_of(value.len() as u64) + value.len();
    }

    let mut output = Vec::with_capacity(payload_size);
    varint::encode_into(values.len() as u64, &mut output);
    for value in values {
        varint::encode_into(value.len() as u64, &mut output);
        output.extend_from_slice(value);
    }

    output
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

    let decode_started = Instant::now();
    let root_hash = match convert_required_array(&mut env, root_hash, "rootHash") {
        Ok(root_hash) => root_hash,
        Err(_) => return 0,
    };
    let decode_elapsed = elapsed_nanos(decode_started);
    let root_hash_len = len_as_u64(root_hash.len());

    let mut adapter = match JavaRawStoreAdapter::new(&mut env, store_adapter) {
        Ok(adapter) => adapter,
        Err(_) => return 0,
    };

    let mut counting_adapter = CountingRawStoreAdapter::new(&mut adapter);
    let core_started = Instant::now();
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
    let core_elapsed = elapsed_nanos(core_started);

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
    trie_handle.counters.add_decode_nanos(decode_elapsed);
    trie_handle.counters.add_jni_bytes_in(root_hash_len);
    trie_handle.counters.add_core_nanos(core_elapsed);
    trie_handle
        .counters
        .add_store_callback_nanos(counting_adapter.stats.callback_nanos);
    trie_handle
        .counters
        .add_store_callback_calls(counting_adapter.stats.callback_calls);

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
    let decode_started = Instant::now();
    let key = match convert_required_array(&mut env, key, "key") {
        Ok(key) => key,
        Err(_) => return std::ptr::null_mut(),
    };
    record_decode_metrics(handle, elapsed_nanos(decode_started), len_as_u64(key.len()));

    let value = match with_trie_mut(handle, |trie| {
        let core_started = Instant::now();
        let value = trie.runtime.get_ref(&key).map(|value| value.to_vec());
        trie.counters.add_core_nanos(elapsed_nanos(core_started));
        value
    }) {
        Ok(value) => value,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            return std::ptr::null_mut();
        }
    };

    let encode_started = Instant::now();
    let output_len = value
        .as_ref()
        .map(|value| len_as_u64(value.len()))
        .unwrap_or(0);
    let output = match value {
        Some(value) => to_byte_array(&mut env, &value, "value").unwrap_or(std::ptr::null_mut()),
        None => std::ptr::null_mut(),
    };
    record_encode_metrics(handle, elapsed_nanos(encode_started), output_len);
    output
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativePut(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
    key: JByteArray,
    value: JByteArray,
) {
    let decode_started = Instant::now();
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
    let mut bytes_in = len_as_u64(key.len());
    if let Some(value) = value.as_ref() {
        bytes_in = bytes_in.saturating_add(len_as_u64(value.len()));
    }
    record_decode_metrics(handle, elapsed_nanos(decode_started), bytes_in);

    if let Err(err) = with_trie_mut(handle, |trie| {
        let core_started = Instant::now();
        match value {
            Some(value) => trie.runtime.put(key, value),
            None => trie.runtime.delete(&key),
        }
        trie.counters.add_core_nanos(elapsed_nanos(core_started));
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
    let decode_started = Instant::now();
    let key = match convert_required_array(&mut env, key, "key") {
        Ok(key) => key,
        Err(_) => return,
    };
    record_decode_metrics(handle, elapsed_nanos(decode_started), len_as_u64(key.len()));

    if let Err(err) = with_trie_mut(handle, |trie| {
        let core_started = Instant::now();
        trie.runtime.delete(&key);
        trie.counters.add_core_nanos(elapsed_nanos(core_started));
    }) {
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
    let decode_started = Instant::now();
    let key = match convert_required_array(&mut env, key, "key") {
        Ok(key) => key,
        Err(_) => return,
    };
    record_decode_metrics(handle, elapsed_nanos(decode_started), len_as_u64(key.len()));

    if let Err(err) = with_trie_mut(handle, |trie| {
        let core_started = Instant::now();
        trie.runtime.delete_recursive(&key);
        trie.counters.add_core_nanos(elapsed_nanos(core_started));
    }) {
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
        let core_started = Instant::now();
        trie.runtime.save_to_store(&mut counting_adapter);
        trie.counters.add_core_nanos(elapsed_nanos(core_started));

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
        trie.counters
            .add_store_callback_nanos(counting_adapter.stats.callback_nanos);
        trie.counters
            .add_store_callback_calls(counting_adapter.stats.callback_calls);
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
    let decode_started = Instant::now();
    let key = match convert_required_array(&mut env, key, "key") {
        Ok(key) => key,
        Err(_) => return -1,
    };
    record_decode_metrics(handle, elapsed_nanos(decode_started), len_as_u64(key.len()));

    let core_started = Instant::now();
    let output = match with_trie_mut(handle, |trie| trie.runtime.get_value_length(&key)) {
        Ok(Some(value_length)) => value_length as jint,
        Ok(None) => -1,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            -1
        }
    };
    if let Some(mut trie_handle) = TRIES.get_mut(&handle) {
        trie_handle.counters.add_core_nanos(elapsed_nanos(core_started));
        trie_handle.counters.add_encode_nanos(0);
        trie_handle.counters.add_jni_bytes_out(4);
    }
    output
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeGetValueHash(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
    key: JByteArray,
) -> jbyteArray {
    let decode_started = Instant::now();
    let key = match convert_required_array(&mut env, key, "key") {
        Ok(key) => key,
        Err(_) => return std::ptr::null_mut(),
    };
    record_decode_metrics(handle, elapsed_nanos(decode_started), len_as_u64(key.len()));

    let value_hash = match with_trie_mut(handle, |trie| {
        let core_started = Instant::now();
        let value_hash = trie.runtime.get_value_hash(&key);
        trie.counters.add_core_nanos(elapsed_nanos(core_started));
        value_hash
    }) {
        Ok(value_hash) => value_hash,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            return std::ptr::null_mut();
        }
    };

    let encode_started = Instant::now();
    let output_len = if value_hash.is_some() { 32 } else { 0 };
    let output = match value_hash {
        Some(value_hash) => {
            to_byte_array(&mut env, &value_hash, "value hash").unwrap_or(std::ptr::null_mut())
        }
        None => std::ptr::null_mut(),
    };
    record_encode_metrics(handle, elapsed_nanos(encode_started), output_len);
    output
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeCollectKeys(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
    size: jint,
) -> jobjectArray {
    let size = if size < 0 { 0 } else { size as usize };

    let keys = match with_trie_mut(handle, |trie| {
        let core_started = Instant::now();
        let keys = trie.runtime.collect_keys(size);
        trie.counters.add_core_nanos(elapsed_nanos(core_started));
        keys
    }) {
        Ok(keys) => keys,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            return std::ptr::null_mut();
        }
    };

    let encoded_bytes = keys
        .iter()
        .fold(0u64, |acc, key| acc.saturating_add(len_as_u64(key.len())));
    let encode_started = Instant::now();
    let output = bytes_vec_to_jobject_array(&mut env, keys).unwrap_or(std::ptr::null_mut());
    record_encode_metrics(handle, elapsed_nanos(encode_started), encoded_bytes);
    output
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeGetStorageKeys(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
    account_address: JByteArray,
) -> jobjectArray {
    let decode_started = Instant::now();
    let account_address = match convert_required_array(&mut env, account_address, "accountAddress") {
        Ok(account_address) => account_address,
        Err(_) => return std::ptr::null_mut(),
    };
    record_decode_metrics(
        handle,
        elapsed_nanos(decode_started),
        len_as_u64(account_address.len()),
    );

    let keys = match with_trie_mut(handle, |trie| {
        let core_started = Instant::now();
        let keys = trie.runtime.get_storage_keys(&account_address);
        trie.counters.add_core_nanos(elapsed_nanos(core_started));
        keys
    }) {
        Ok(keys) => keys,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            return std::ptr::null_mut();
        }
    };

    let encoded_bytes = keys
        .iter()
        .fold(0u64, |acc, key| acc.saturating_add(len_as_u64(key.len())));
    let encode_started = Instant::now();
    let output = bytes_vec_to_jobject_array(&mut env, keys).unwrap_or(std::ptr::null_mut());
    record_encode_metrics(handle, elapsed_nanos(encode_started), encoded_bytes);
    output
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeGetStorageKeysPacked(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
    account_address: JByteArray,
) -> jbyteArray {
    let decode_started = Instant::now();
    let account_address = match convert_required_array(&mut env, account_address, "accountAddress") {
        Ok(account_address) => account_address,
        Err(_) => return std::ptr::null_mut(),
    };
    record_decode_metrics(
        handle,
        elapsed_nanos(decode_started),
        len_as_u64(account_address.len()),
    );

    let packed_keys = match with_trie_mut(handle, |trie| {
        let core_started = Instant::now();
        let keys = trie.runtime.get_storage_keys(&account_address);
        let packed = encode_storage_keys_packed(&keys);
        trie.counters.add_core_nanos(elapsed_nanos(core_started));
        packed
    }) {
        Ok(packed_keys) => packed_keys,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            return std::ptr::null_mut();
        }
    };

    let encode_started = Instant::now();
    let output = to_byte_array(&mut env, &packed_keys, "packed storage keys")
        .unwrap_or(std::ptr::null_mut());
    record_encode_metrics(
        handle,
        elapsed_nanos(encode_started),
        len_as_u64(packed_keys.len()),
    );
    output
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeRootHash(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jbyteArray {
    let root_hash = match with_trie_mut(handle, |trie| {
        let core_started = Instant::now();
        let root_hash = trie.runtime.root_hash();
        trie.counters.add_core_nanos(elapsed_nanos(core_started));
        root_hash
    }) {
        Ok(root_hash) => root_hash,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            return std::ptr::null_mut();
        }
    };

    let encode_started = Instant::now();
    let output = to_byte_array(&mut env, &root_hash, "root hash").unwrap_or(std::ptr::null_mut());
    record_encode_metrics(handle, elapsed_nanos(encode_started), 32);
    output
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeCurrentRootHash(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jbyteArray {
    let root_hash = match with_trie_mut(handle, |trie| {
        let core_started = Instant::now();
        let root_hash = trie.runtime.current_root_hash();
        trie.counters.add_core_nanos(elapsed_nanos(core_started));
        root_hash
    }) {
        Ok(root_hash) => root_hash,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            return std::ptr::null_mut();
        }
    };

    let encode_started = Instant::now();
    let output = to_byte_array(&mut env, &root_hash, "current root hash")
        .unwrap_or(std::ptr::null_mut());
    record_encode_metrics(handle, elapsed_nanos(encode_started), 32);
    output
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeGetPerfCounters(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jlongArray {
    let counters = match with_trie_mut(handle, |trie| {
        let core_started = Instant::now();
        let counters = trie.counters.as_long_vec();
        trie.counters.add_core_nanos(elapsed_nanos(core_started));
        counters
    }) {
        Ok(counters) => counters,
        Err(err) => {
            throw_illegal_argument(&mut env, err);
            return std::ptr::null_mut();
        }
    };

    let encode_started = Instant::now();
    let output = to_long_array(&mut env, &counters, "perf counters").unwrap_or(std::ptr::null_mut());
    record_encode_metrics(
        handle,
        elapsed_nanos(encode_started),
        len_as_u64(counters.len().saturating_mul(std::mem::size_of::<jlong>())),
    );
    output
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

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeBenchmarkNoop(
    mut env: JNIEnv,
    _class: JClass,
    iterations: jint,
) -> jlong {
    if iterations <= 0 {
        throw_illegal_argument(&mut env, "iterations must be greater than zero");
        return 0;
    }

    let started = Instant::now();
    let mut checksum: u64 = 0;
    for index in 0..(iterations as u64) {
        checksum ^= index.wrapping_mul(0x9e37_79b9_7f4a_7c15);
    }
    let elapsed = elapsed_nanos(started);
    (elapsed ^ checksum) as jlong
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeBenchmarkRoundtrip(
    mut env: JNIEnv,
    _class: JClass,
    payload: JByteArray,
    iterations: jint,
) -> jlong {
    if iterations <= 0 {
        throw_illegal_argument(&mut env, "iterations must be greater than zero");
        return 0;
    }

    let payload = match convert_required_array(&mut env, payload, "payload") {
        Ok(payload) => payload,
        Err(_) => return 0,
    };

    let started = Instant::now();
    let mut checksum: u64 = 0;
    for index in 0..(iterations as usize) {
        let copy = payload.clone();
        checksum = checksum
            .wrapping_add(len_as_u64(copy.len()))
            .wrapping_add(index as u64);
        if let Some(first) = copy.first() {
            checksum ^= *first as u64;
        }
    }
    let elapsed = elapsed_nanos(started);
    (elapsed ^ checksum) as jlong
}

#[cfg(test)]
mod tests {
    use super::encode_storage_keys_packed;
    use crate::varint::decode_from_slice;

    #[test]
    fn storage_keys_packed_round_trip() {
        let values = vec![vec![0x01], vec![0xaa, 0xbb], vec![0x10; 260]];
        let encoded = encode_storage_keys_packed(&values);

        let mut offset = 0usize;
        let count = decode_from_slice(&encoded, &mut offset).expect("count varint");
        assert_eq!(count as usize, values.len());

        let mut decoded = Vec::new();
        for _ in 0..count {
            let len = decode_from_slice(&encoded, &mut offset).expect("len varint") as usize;
            let end = offset + len;
            decoded.push(encoded[offset..end].to_vec());
            offset = end;
        }

        assert_eq!(decoded, values);
        assert_eq!(offset, encoded.len());
    }
}
