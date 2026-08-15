from pathlib import Path

# rust/src/db.rs
path = Path('rust/src/db.rs')
text = path.read_text()
text = text.replace('collections::HashMap,', 'collections::{HashMap, HashSet},', 1)
text = text.replace(
    'static DATABASES: Lazy<RwLock<HashMap<String, OpenDatabase>>> =\n    Lazy::new(|| RwLock::new(HashMap::new()));',
    'static DATABASES: Lazy<RwLock<HashMap<String, OpenDatabase>>> =\n    Lazy::new(|| RwLock::new(HashMap::new()));\nstatic COMPACTING: Lazy<RwLock<HashSet<String>>> =\n    Lazy::new(|| RwLock::new(HashSet::new()));',
    1,
)
old = '''fn database(name: &str) -> Result<(Arc<Database>, Arc<EncryptionState>), String> {
    DATABASES
        .read()
        .get(name)
        .map(|entry| (Arc::clone(&entry.db), Arc::clone(&entry.encryption)))
        .ok_or_else(|| format!("box '{name}' is not open"))
}
'''
new = '''fn database(name: &str) -> Result<(Arc<Database>, Arc<EncryptionState>), String> {
    if let Some(entry) = DATABASES.read().get(name) {
        return Ok((Arc::clone(&entry.db), Arc::clone(&entry.encryption)));
    }
    if COMPACTING.read().contains(name) {
        return Err(format!("box '{name}' is compacting; retry later"));
    }
    Err(format!("box '{name}' is not open"))
}
'''
if old not in text:
    raise SystemExit('database function marker not found')
text = text.replace(old, new, 1)
old = '''    let path = file_path(name)?;
    let existed = path.exists();
    let mut databases = DATABASES.write();

    if let Some(entry) = databases.get_mut(name) {'''
new = '''    let path = file_path(name)?;
    let existed = path.exists();
    let mut databases = DATABASES.write();

    if COMPACTING.read().contains(name) {
        return Err(format!("box '{name}' is compacting; retry later"));
    }

    if let Some(entry) = databases.get_mut(name) {'''
if old not in text:
    raise SystemExit('open marker not found')
text = text.replace(old, new, 1)
old = '''pub fn compact(name: &str) -> Result<bool, String> {
    let mut databases = DATABASES.write();
    let entry = databases
        .get_mut(name)
        .ok_or_else(|| format!("box '{name}' is not open"))?;
    if entry.handles != 1 {
        return Err("compact requires exactly one open box handle".to_string());
    }
    let db = Arc::get_mut(&mut entry.db)
        .ok_or_else(|| "box is busy; retry compact when no operations are in flight".to_string())?;

    let mut compacted = false;
    while db.compact().map_err(|e| e.to_string())? {
        compacted = true;
    }
    Ok(compacted)
}
'''
new = '''pub fn compact(name: &str) -> Result<bool, String> {
    let entry = {
        let mut databases = DATABASES.write();
        let current = databases
            .get(name)
            .ok_or_else(|| format!("box '{name}' is not open"))?;
        if current.handles != 1 {
            return Err("compact requires exactly one open box handle".to_string());
        }
        if Arc::strong_count(&current.db) != 1 {
            return Err("box is busy; retry compact when no operations are in flight".to_string());
        }
        COMPACTING.write().insert(name.to_string());
        databases
            .remove(name)
            .expect("entry checked immediately before removal")
    };

    let OpenDatabase {
        db,
        handles,
        encryption,
    } = entry;
    let mut database = match Arc::try_unwrap(db) {
        Ok(database) => database,
        Err(db) => {
            let mut databases = DATABASES.write();
            databases.insert(
                name.to_string(),
                OpenDatabase {
                    db,
                    handles,
                    encryption,
                },
            );
            COMPACTING.write().remove(name);
            return Err("box is busy; retry compact when no operations are in flight".to_string());
        }
    };

    let result = (|| {
        let mut compacted = false;
        while database.compact().map_err(|e| e.to_string())? {
            compacted = true;
        }
        Ok(compacted)
    })();

    let mut databases = DATABASES.write();
    databases.insert(
        name.to_string(),
        OpenDatabase {
            db: Arc::new(database),
            handles,
            encryption,
        },
    );
    COMPACTING.write().remove(name);
    result
}
'''
if old not in text:
    raise SystemExit('compact block marker not found')
text = text.replace(old, new, 1)
path.write_text(text)

# rust/src/api.rs: serialize open/close against compaction using the existing per-box mutation lock.
path = Path('rust/src/api.rs')
text = path.read_text()
old = '''#[frb(sync)]
pub fn open_box(name: String, encryption_key: Option<String>) -> Result<(), String> {
    db::open(&name, encryption_key.as_deref())
}

#[frb(sync)]
pub fn close_box(name: String) -> Result<(), String> {
    db::close(&name);
    Ok(())
}
'''
new = '''#[frb(sync)]
pub fn open_box(name: String, encryption_key: Option<String>) -> Result<(), String> {
    let mutation_lock = mutation_lock(&name);
    let _mutation_guard = mutation_lock.lock();
    db::open(&name, encryption_key.as_deref())
}

#[frb(sync)]
pub fn close_box(name: String) -> Result<(), String> {
    let mutation_lock = mutation_lock(&name);
    let _mutation_guard = mutation_lock.lock();
    db::close(&name);
    Ok(())
}
'''
if old not in text:
    raise SystemExit('api open/close marker not found')
text = text.replace(old, new, 1)
path.write_text(text)

# Makefile: local preflight must match CI formatting scope.
path = Path('Makefile')
text = path.read_text()
text = text.replace('dart format lib test', 'dart format lib test example')
text = text.replace(
    'dart format --output=none --set-exit-if-changed lib test',
    'dart format --output=none --set-exit-if-changed lib test example',
)
path.write_text(text)
