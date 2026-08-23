mod support;

use std::sync::Mutex;

use rust_lib_dxtr_box::{api, BoxHandle, DxtrBox};
use support::conformance::{assert_storage_contract, StorageBoxContract};

static TEST_LOCK: Mutex<()> = Mutex::new(());

struct RustNativeBox(BoxHandle);

impl StorageBoxContract for RustNativeBox {
    fn put(&self, key: &str, value: Vec<u8>) {
        self.0.put(key, value).unwrap();
    }

    fn put_all(&self, entries: Vec<(String, Vec<u8>)>) {
        self.0.put_all(entries).unwrap();
    }

    fn get(&self, key: &str) -> Option<Vec<u8>> {
        self.0.get(key).unwrap()
    }

    fn contains_key(&self, key: &str) -> bool {
        self.0.contains_key(key).unwrap()
    }

    fn get_all(&self, keys: &[String]) -> Vec<(String, Vec<u8>)> {
        self.0
            .get_all(keys)
            .unwrap()
            .into_iter()
            .map(|record| (record.key, record.value))
            .collect()
    }

    fn delete(&self, key: &str) {
        self.0.delete(key).unwrap();
    }

    fn delete_all(&self, keys: &[String]) -> Vec<String> {
        self.0.delete_all(keys).unwrap()
    }

    fn clear(&self) {
        self.0.clear().unwrap();
    }

    fn all_keys(&self) -> Vec<String> {
        self.0.all_keys().unwrap()
    }

    fn len(&self) -> u64 {
        self.0.len().unwrap()
    }
}

struct FrbAdapterBox {
    name: String,
}

impl StorageBoxContract for FrbAdapterBox {
    fn put(&self, key: &str, value: Vec<u8>) {
        api::put(self.name.clone(), key.to_string(), value).unwrap();
    }

    fn put_all(&self, entries: Vec<(String, Vec<u8>)>) {
        api::put_all(self.name.clone(), entries).unwrap();
    }

    fn get(&self, key: &str) -> Option<Vec<u8>> {
        api::get(self.name.clone(), key.to_string()).unwrap()
    }

    fn contains_key(&self, key: &str) -> bool {
        api::contains_key(self.name.clone(), key.to_string()).unwrap()
    }

    fn get_all(&self, keys: &[String]) -> Vec<(String, Vec<u8>)> {
        api::get_all(self.name.clone(), keys.to_vec())
            .unwrap()
            .into_iter()
            .map(|record| (record.key, record.value))
            .collect()
    }

    fn delete(&self, key: &str) {
        api::delete(self.name.clone(), key.to_string()).unwrap();
    }

    fn delete_all(&self, keys: &[String]) -> Vec<String> {
        api::delete_all(self.name.clone(), keys.to_vec()).unwrap()
    }

    fn clear(&self) {
        api::clear(self.name.clone()).unwrap();
    }

    fn all_keys(&self) -> Vec<String> {
        api::get_all_keys(self.name.clone()).unwrap()
    }

    fn len(&self) -> u64 {
        api::length(self.name.clone()).unwrap()
    }
}

#[test]
fn rust_native_frontend_satisfies_shared_storage_contract() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();

    let db = DxtrBox::open(dir.path()).unwrap();
    let box_ = RustNativeBox(db.box_("conformance_rust_native").unwrap());
    assert_storage_contract(&box_);
    box_.0.close().unwrap();
}

#[test]
fn frb_adapter_frontend_satisfies_shared_storage_contract() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let name = "conformance_frb_adapter".to_string();

    api::init_db(dir.path().to_string_lossy().into_owned()).unwrap();
    api::open_box(name.clone(), None).unwrap();
    let box_ = FrbAdapterBox { name: name.clone() };
    assert_storage_contract(&box_);
    api::close_box(name).unwrap();
}
