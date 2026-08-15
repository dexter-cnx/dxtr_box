from pathlib import Path

path = Path('rust/src/db.rs')
text = path.read_text()

meta_marker = 'const META: TableDefinition<&str, &[u8]> = TableDefinition::new("meta");\n'
meta_insert = meta_marker + '#[cfg(not(feature = "full"))]\nconst INDEX_DEFINITIONS_GUARD: TableDefinition<&str, &str> =\n    TableDefinition::new("index_definitions");\n'
if meta_marker not in text:
    raise SystemExit('meta table marker not found')
text = text.replace(meta_marker, meta_insert, 1)

open_marker = 'pub fn open(name: &str, encryption_key: Option<&str>) -> Result<(), String> {\n'
guard_fn = '''#[cfg(not(feature = "full"))]\nfn reject_persisted_indexes_without_full(db: &Database) -> Result<(), String> {\n    let read = db.begin_read().map_err(|e| e.to_string())?;\n    if let Ok(table) = read.open_table(INDEX_DEFINITIONS_GUARD) {\n        if table.len().map_err(|e| e.to_string())? > 0 {\n            return Err(\n                "box has persisted indexes and requires the full native profile for safe mutation"\n                    .to_string(),\n            );\n        }\n    }\n    Ok(())\n}\n\n'''
if open_marker not in text:
    raise SystemExit('open marker not found')
text = text.replace(open_marker, guard_fn + open_marker, 1)

full_marker = '    #[cfg(feature = "full")]\n    index::ensure_tables(&db)?;\n'
profile_guard = '''    #[cfg(not(feature = "full"))]\n    reject_persisted_indexes_without_full(&db)?;\n\n'''
if full_marker not in text:
    raise SystemExit('full index ensure marker not found')
text = text.replace(full_marker, profile_guard + full_marker, 1)

path.write_text(text)
