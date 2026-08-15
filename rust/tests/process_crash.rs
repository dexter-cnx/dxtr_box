use std::{
    env,
    io::{BufRead, BufReader, Write},
    process::{Command, Stdio},
    thread,
    time::Duration,
};

use rust_lib_dxtr_box::{close_box, get, init_db, open_box, put, put_all};
use tempfile::tempdir;

const CHILD_MODE: &str = "DXTR_BOX_PROCESS_CRASH_CHILD";
const ROOT_PATH: &str = "DXTR_BOX_PROCESS_CRASH_ROOT";
const COMMITTED_MARKER: &str = "DXTR_BOX_COMMITTED";

fn encoded<T: serde::Serialize>(value: &T) -> Vec<u8> {
    rmp_serde::to_vec(value).expect("encode MessagePack fixture")
}

fn child_workload() {
    let root = env::var(ROOT_PATH).expect("child root path");
    init_db(root).expect("child init");

    open_box("plain".to_string(), None).expect("open plaintext box");
    put(
        "plain".to_string(),
        "first".to_string(),
        encoded(&"committed-first"),
    )
    .expect("first committed write");
    put_all(
        "plain".to_string(),
        vec![
            ("second".to_string(), encoded(&42_u64)),
            ("third".to_string(), encoded(&vec![1_u8, 2, 3, 4])),
        ],
    )
    .expect("second committed transaction");
    put(
        "plain".to_string(),
        "after-batch".to_string(),
        encoded(&true),
    )
    .expect("third committed transaction");

    #[cfg(feature = "encryption")]
    {
        open_box(
            "secure".to_string(),
            Some("crash-reopen-secret".to_string()),
        )
        .expect("open encrypted box");
        put(
            "secure".to_string(),
            "token".to_string(),
            encoded(&"encrypted-committed"),
        )
        .expect("encrypted committed write");
    }

    println!("{COMMITTED_MARKER}");
    std::io::stdout().flush().expect("flush committed marker");

    // Keep the boxes open. The parent kills this process after seeing the
    // marker, so no Box close / redb Database drop path is exercised here.
    loop {
        thread::sleep(Duration::from_secs(60));
    }
}

#[test]
fn process_crash_recovers_committed_plaintext_and_encrypted_state() {
    if env::var(CHILD_MODE).as_deref() == Ok("1") {
        child_workload();
        return;
    }

    let root = tempdir().expect("temporary crash test directory");
    let current_exe = env::current_exe().expect("current Rust test executable");
    let mut child = Command::new(current_exe)
        .arg("--exact")
        .arg("process_crash_recovers_committed_plaintext_and_encrypted_state")
        .arg("--nocapture")
        .env(CHILD_MODE, "1")
        .env(ROOT_PATH, root.path())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .expect("spawn crash writer child");

    let stdout = child.stdout.take().expect("child stdout");
    let reader = BufReader::new(stdout);
    let mut committed = false;
    for line in reader.lines() {
        let line = line.expect("read child output");
        if line.contains(COMMITTED_MARKER) {
            committed = true;
            break;
        }
    }
    assert!(committed, "child exited before confirming committed writes");

    child.kill().expect("kill child after committed marker");
    let status = child.wait().expect("wait for killed child");
    assert!(!status.success(), "crash child unexpectedly exited cleanly");

    init_db(root.path().to_string_lossy().into_owned()).expect("parent reopen init");

    open_box("plain".to_string(), None).expect("reopen plaintext box after process kill");
    assert_eq!(
        get("plain".to_string(), "first".to_string()).expect("read first"),
        Some(encoded(&"committed-first"))
    );
    assert_eq!(
        get("plain".to_string(), "second".to_string()).expect("read second"),
        Some(encoded(&42_u64))
    );
    assert_eq!(
        get("plain".to_string(), "third".to_string()).expect("read third"),
        Some(encoded(&vec![1_u8, 2, 3, 4]))
    );
    assert_eq!(
        get("plain".to_string(), "after-batch".to_string()).expect("read after-batch"),
        Some(encoded(&true))
    );
    close_box("plain".to_string()).expect("close reopened plaintext box");

    #[cfg(feature = "encryption")]
    {
        open_box(
            "secure".to_string(),
            Some("crash-reopen-secret".to_string()),
        )
        .expect("reopen encrypted box after process kill");
        assert_eq!(
            get("secure".to_string(), "token".to_string()).expect("read encrypted token"),
            Some(encoded(&"encrypted-committed"))
        );
        close_box("secure".to_string()).expect("close reopened encrypted box");
    }
}
