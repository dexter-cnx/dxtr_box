use std::sync::{Arc, Barrier, Mutex};

use rust_lib_dxtr_box::{BoxHandle, DxtrBox, DxtrBoxError};

static TEST_LOCK: Mutex<()> = Mutex::new(());

fn assert_send_sync<T: Send + Sync>() {}

#[test]
fn rust_native_handles_are_send_and_sync() {
    assert_send_sync::<DxtrBox>();
    assert_send_sync::<BoxHandle>();
}

#[test]
fn rust_native_crud_is_available_in_every_profile() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let db = DxtrBox::open(dir.path()).unwrap();
    let items = db.box_("items").unwrap();

    items.put("one", vec![1]).unwrap();
    items.put("two", vec![2]).unwrap();

    assert_eq!(items.get("one").unwrap(), Some(vec![1]));
    assert!(items.contains_key("two").unwrap());
    assert_eq!(items.len().unwrap(), 2);

    items.close().unwrap();
}

#[test]
fn rust_native_same_box_mutations_are_safe_across_threads() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let db = DxtrBox::open(dir.path()).unwrap();
    let items = Arc::new(db.box_("items").unwrap());

    let threads = (0u8..8)
        .map(|worker| {
            let items = Arc::clone(&items);
            std::thread::spawn(move || {
                for offset in 0u8..16 {
                    let key = format!("worker-{worker}-{offset}");
                    let value = vec![0x92, worker, offset];
                    items.put(key, value).unwrap();
                }
            })
        })
        .collect::<Vec<_>>();

    for thread in threads {
        thread.join().unwrap();
    }

    assert_eq!(items.len().unwrap(), 128);
    assert_eq!(items.get("worker-7-15").unwrap(), Some(vec![0x92, 7, 15]));

    drop(items);
}

#[test]
fn independent_handles_support_concurrent_readers_and_writers() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let db = DxtrBox::open(dir.path()).unwrap();
    let writer = Arc::new(db.box_("items").unwrap());
    let reader_a = Arc::new(db.box_("items").unwrap());
    let reader_b = Arc::new(db.box_("items").unwrap());
    let start = Arc::new(Barrier::new(3));

    writer.put("seed", vec![0]).unwrap();

    let writer_thread = {
        let writer = Arc::clone(&writer);
        let start = Arc::clone(&start);
        std::thread::spawn(move || {
            start.wait();
            for value in 1u8..=64 {
                writer.put("shared", vec![value]).unwrap();
                writer.put(format!("write-{value}"), vec![value]).unwrap();
            }
        })
    };

    let reader_threads = [reader_a, reader_b]
        .into_iter()
        .map(|reader| {
            let start = Arc::clone(&start);
            std::thread::spawn(move || {
                start.wait();
                for _ in 0..128 {
                    assert_eq!(reader.get("seed").unwrap(), Some(vec![0]));
                    if let Some(value) = reader.get("shared").unwrap() {
                        assert_eq!(value.len(), 1);
                        assert!((1..=64).contains(&value[0]));
                    }
                }
            })
        })
        .collect::<Vec<_>>();

    writer_thread.join().unwrap();
    for thread in reader_threads {
        thread.join().unwrap();
    }

    assert_eq!(writer.get("shared").unwrap(), Some(vec![64]));
    assert_eq!(writer.len().unwrap(), 66);
}

#[test]
fn concurrent_mutations_remain_durable_after_all_handles_close_and_reopen() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let db = DxtrBox::open(dir.path()).unwrap();
    let first = Arc::new(db.box_("items").unwrap());
    let second = Arc::new(db.box_("items").unwrap());

    let threads = [Arc::clone(&first), Arc::clone(&second)]
        .into_iter()
        .enumerate()
        .map(|(worker, handle)| {
            std::thread::spawn(move || {
                for offset in 0..32 {
                    let key = format!("worker-{worker}-{offset}");
                    handle.put(key, vec![worker as u8, offset as u8]).unwrap();
                }
            })
        })
        .collect::<Vec<_>>();

    for thread in threads {
        thread.join().unwrap();
    }

    first.close().unwrap();
    second.close().unwrap();

    let reopened = db.box_("items").unwrap();
    assert_eq!(reopened.len().unwrap(), 64);
    assert_eq!(
        reopened.get("worker-0-31").unwrap(),
        Some(vec![0, 31])
    );
    assert_eq!(
        reopened.get("worker-1-31").unwrap(),
        Some(vec![1, 31])
    );
    reopened.close().unwrap();
}

#[test]
fn multiple_native_handles_keep_the_box_open_until_the_last_handle_closes() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let db = DxtrBox::open(dir.path()).unwrap();

    let first = db.box_("items").unwrap();
    let second = db.box_("items").unwrap();

    first.put("shared", vec![1]).unwrap();
    first.close().unwrap();

    assert_eq!(second.get("shared").unwrap(), Some(vec![1]));
    second.put("after-first-close", vec![2]).unwrap();
    second.close().unwrap();

    let reopened = db.box_("items").unwrap();
    assert_eq!(reopened.get("after-first-close").unwrap(), Some(vec![2]));
    reopened.close().unwrap();
}

#[cfg(feature = "encryption")]
#[test]
fn encryption_profile_supports_native_encrypted_reopen() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let db = DxtrBox::open(dir.path()).unwrap();

    let secure = db
        .box_with_key("secure", Some("correct horse battery staple"))
        .unwrap();
    secure.put("secret", vec![42]).unwrap();
    secure.close().unwrap();

    let wrong = db.box_with_key("secure", Some("wrong key")).unwrap_err();
    assert!(matches!(wrong, DxtrBoxError::Engine { .. }));

    let secure = db
        .box_with_key("secure", Some("correct horse battery staple"))
        .unwrap();
    assert_eq!(secure.get("secret").unwrap(), Some(vec![42]));
    secure.close().unwrap();
}

#[cfg(not(feature = "full"))]
#[test]
fn reduced_profiles_report_full_only_capabilities_as_unsupported() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let db = DxtrBox::open(dir.path()).unwrap();
    let items = db.box_("items").unwrap();

    assert!(matches!(
        items.create_index("by_value", "value"),
        Err(DxtrBoxError::UnsupportedFeature { .. })
    ));
    assert!(matches!(
        items.query(),
        Err(DxtrBoxError::UnsupportedFeature { .. })
    ));

    items.close().unwrap();
}
