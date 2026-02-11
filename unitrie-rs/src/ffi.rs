use crate::trie::Unitrie;
use jni::objects::{JByteArray, JClass};
use jni::sys::{jbyteArray, jlong};
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
        Some(value) => match env.byte_array_from_slice(&value) {
            Ok(bytes) => bytes.into_raw(),
            Err(err) => {
                throw_illegal_state(&mut env, format!("could not return value: {err}"));
                std::ptr::null_mut()
            }
        },
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
pub extern "system" fn Java_co_rsk_trie_engine_rust_RustUnitrieBridge_nativeRootHash(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jbyteArray {
    let root_hash = match with_trie_mut(&mut env, handle, |trie| trie.root_hash()) {
        Some(root_hash) => root_hash,
        None => return std::ptr::null_mut(),
    };

    match env.byte_array_from_slice(&root_hash) {
        Ok(bytes) => bytes.into_raw(),
        Err(err) => {
            throw_illegal_state(&mut env, format!("could not return root hash: {err}"));
            std::ptr::null_mut()
        }
    }
}
