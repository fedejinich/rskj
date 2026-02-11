use crate::core_trie::Unitrie;
use crate::store_adapter::RawStoreAdapter;
use jni::objects::{JByteArray, JClass, JObject, JValue};
use jni::sys::{jbyteArray, jint, jlong, jobjectArray};
use jni::JNIEnv;
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::Mutex;

static NEXT_HANDLE: AtomicI64 = AtomicI64::new(1);
static TRIES: Lazy<Mutex<HashMap<i64, Unitrie>>> = Lazy::new(|| Mutex::new(HashMap::new()));

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

fn to_byte_array(env: &mut JNIEnv, bytes: &[u8], error_context: &str) -> Option<jbyteArray> {
    match env.byte_array_from_slice(bytes) {
        Ok(array) => Some(array.into_raw()),
        Err(err) => {
            throw_illegal_state(env, format!("could not return {error_context}: {err}"));
            None
        }
    }
}

fn with_trie_mut<T>(
    env: &mut JNIEnv,
    handle: jlong,
    f: impl FnOnce(&mut Unitrie) -> T,
) -> Option<T> {
    let mut tries = match TRIES.lock() {
        Ok(tries) => tries,
        Err(_) => {
            throw_illegal_state(env, "unitrie-rs handle table is poisoned");
            return None;
        }
    };

    let trie = match tries.get_mut(&handle) {
        Some(trie) => trie,
        None => {
            throw_illegal_argument(env, format!("unknown trie handle {handle}"));
            return None;
        }
    };

    Some(f(trie))
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
) -> jlong {
    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    let mut tries = match TRIES.lock() {
        Ok(tries) => tries,
        Err(_) => {
            throw_illegal_state(&mut env, "unitrie-rs handle table is poisoned");
            return 0;
        }
    };

    tries.insert(handle, Unitrie::new());
    handle
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeCreateTrieFromRoot<
    'a,
>(
    mut env: JNIEnv<'a>,
    _class: JClass<'a>,
    root_hash: JByteArray<'a>,
    store_adapter: JObject<'a>,
) -> jlong {
    let root_hash = match convert_required_array(&mut env, root_hash, "rootHash") {
        Ok(root_hash) => root_hash,
        Err(_) => return 0,
    };

    let mut adapter = match JavaRawStoreAdapter::new(&mut env, store_adapter) {
        Ok(adapter) => adapter,
        Err(_) => return 0,
    };

    let trie = match Unitrie::from_persisted_root(&root_hash, &mut adapter) {
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
    let mut tries = match TRIES.lock() {
        Ok(tries) => tries,
        Err(_) => {
            throw_illegal_state(&mut env, "unitrie-rs handle table is poisoned");
            return 0;
        }
    };

    tries.insert(handle, trie);
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

    if let Ok(mut tries) = TRIES.lock() {
        tries.remove(&handle);
    }
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

    let value = match with_trie_mut(&mut env, handle, |trie| trie.get(&key)) {
        Some(value) => value,
        None => return std::ptr::null_mut(),
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

    let _ = with_trie_mut(&mut env, handle, |trie| match value {
        Some(value) => trie.put(key, value),
        None => trie.delete(&key),
    });
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

    let _ = with_trie_mut(&mut env, handle, |trie| trie.delete(&key));
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

    let _ = with_trie_mut(&mut env, handle, |trie| trie.delete_recursive(&key));
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeSave<'a>(
    mut env: JNIEnv<'a>,
    _class: JClass<'a>,
    handle: jlong,
    store_adapter: JObject<'a>,
) {
    let mut trie_snapshot = match with_trie_mut(&mut env, handle, |trie| trie.clone()) {
        Some(trie_snapshot) => trie_snapshot,
        None => return,
    };

    let mut adapter = match JavaRawStoreAdapter::new(&mut env, store_adapter) {
        Ok(adapter) => adapter,
        Err(_) => return,
    };

    trie_snapshot.save_to_store(&mut adapter);
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

    match with_trie_mut(&mut env, handle, |trie| trie.get_value_length(&key)) {
        Some(Some(value_length)) => value_length as jint,
        Some(None) => -1,
        None => -1,
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

    let value_hash = match with_trie_mut(&mut env, handle, |trie| trie.get_value_hash(&key)) {
        Some(value_hash) => value_hash,
        None => return std::ptr::null_mut(),
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

    let keys = match with_trie_mut(&mut env, handle, |trie| trie.collect_keys(size)) {
        Some(keys) => keys,
        None => return std::ptr::null_mut(),
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
    let account_address = match convert_required_array(&mut env, account_address, "accountAddress")
    {
        Ok(account_address) => account_address,
        Err(_) => return std::ptr::null_mut(),
    };

    let keys = match with_trie_mut(&mut env, handle, |trie| {
        trie.get_storage_keys(&account_address)
    }) {
        Some(keys) => keys,
        None => return std::ptr::null_mut(),
    };

    bytes_vec_to_jobject_array(&mut env, keys).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeRootHash(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jbyteArray {
    let root_hash = match with_trie_mut(&mut env, handle, |trie| trie.root_hash()) {
        Some(root_hash) => root_hash,
        None => return std::ptr::null_mut(),
    };

    to_byte_array(&mut env, &root_hash, "root hash").unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeCurrentRootHash(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jbyteArray {
    let root_hash = match with_trie_mut(&mut env, handle, |trie| trie.current_root_hash()) {
        Some(root_hash) => root_hash,
        None => return std::ptr::null_mut(),
    };

    to_byte_array(&mut env, &root_hash, "current root hash").unwrap_or(std::ptr::null_mut())
}
