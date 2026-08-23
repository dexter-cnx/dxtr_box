pub trait StorageBoxContract {
    fn put(&self, key: &str, value: Vec<u8>);
    fn put_all(&self, entries: Vec<(String, Vec<u8>)>);
    fn get(&self, key: &str) -> Option<Vec<u8>>;
    fn contains_key(&self, key: &str) -> bool;
    fn get_all(&self, keys: &[String]) -> Vec<(String, Vec<u8>)>;
    fn delete(&self, key: &str);
    fn delete_all(&self, keys: &[String]) -> Vec<String>;
    fn clear(&self);
    fn all_keys(&self) -> Vec<String>;
    fn len(&self) -> u64;
}

pub fn assert_storage_contract(box_: &impl StorageBoxContract) {
    let alpha_v1 = vec![0x91, 0x01];
    let alpha_v2 = vec![0x91, 0x02];
    let beta = vec![0x91, 0x03];
    let gamma = vec![0x91, 0x04];

    assert_eq!(box_.len(), 0);
    assert_eq!(box_.get("missing"), None);
    assert!(!box_.contains_key("missing"));

    box_.put("alpha", alpha_v1.clone());
    assert_eq!(box_.get("alpha"), Some(alpha_v1));
    assert!(box_.contains_key("alpha"));
    assert_eq!(box_.len(), 1);

    box_.put("alpha", alpha_v2.clone());
    assert_eq!(box_.get("alpha"), Some(alpha_v2.clone()));
    assert_eq!(box_.len(), 1, "overwrite must not grow length");

    box_.put_all(vec![
        ("beta".to_string(), beta.clone()),
        ("gamma".to_string(), gamma.clone()),
    ]);
    assert_eq!(box_.len(), 3);

    let batch = box_.get_all(&[
        "gamma".to_string(),
        "missing".to_string(),
        "alpha".to_string(),
        "gamma".to_string(),
    ]);
    assert_eq!(
        batch,
        vec![
            ("gamma".to_string(), gamma.clone()),
            ("alpha".to_string(), alpha_v2),
            ("gamma".to_string(), gamma),
        ],
        "batch reads must preserve hit order and duplicates while omitting misses"
    );

    let mut keys = box_.all_keys();
    keys.sort();
    assert_eq!(keys, vec!["alpha", "beta", "gamma"]);

    box_.delete("missing");
    assert_eq!(box_.len(), 3, "deleting a missing key is idempotent");

    box_.delete("beta");
    assert!(!box_.contains_key("beta"));
    assert_eq!(box_.len(), 2);

    let deleted = box_.delete_all(&[
        "missing".to_string(),
        "alpha".to_string(),
        "alpha".to_string(),
    ]);
    assert_eq!(deleted, vec!["alpha".to_string()]);
    assert_eq!(box_.len(), 1);

    box_.clear();
    assert_eq!(box_.len(), 0);
    assert!(box_.all_keys().is_empty());
}
