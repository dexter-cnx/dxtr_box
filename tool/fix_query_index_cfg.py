from pathlib import Path

path = Path('rust/src/db.rs')
text = path.read_text()

replacements = {
    '        let old = table\n            .get(key)': '        let _old = table\n            .get(key)',
    '        index::maintain_put(&write, key, old.as_deref(), value)?;': '        index::maintain_put(&write, key, _old.as_deref(), value)?;',
    '        for (key, plaintext, stored) in &stored_entries {': '        for (key, _plaintext, stored) in &stored_entries {',
    '            let old = table\n                .get(*key)': '            let _old = table\n                .get(*key)',
    '            index::maintain_put(&write, key, old.as_deref(), plaintext)?;': '            index::maintain_put(&write, key, _old.as_deref(), _plaintext)?;',
    '        if let Some(old) = old.as_deref() {': '        if let Some(_old) = _old.as_deref() {',
    '            index::maintain_delete(&write, key, old)?;': '            index::maintain_delete(&write, key, _old)?;',
    '            let old = table\n                .get(key.as_str())': '            let _old = table\n                .get(key.as_str())',
    '            if let Some(old) = old {': '            if let Some(_old) = _old {',
    '                index::maintain_delete(&write, key, &old)?;': '                index::maintain_delete(&write, key, &_old)?;',
}

for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f'expected cfg cleanup pattern not found: {old!r}')
    text = text.replace(old, new, 1)

# put() and delete() intentionally have the same retrieval shape. The first
# replacement above updates put(); rename the remaining delete() binding too so
# reduced profiles do not leave an unused local after the full-only maintenance
# block is compiled out.
delete_binding = '        let old = table\n            .get(key)'
if delete_binding not in text:
    raise SystemExit('expected delete cfg binding not found')
text = text.replace(
    delete_binding,
    '        let _old = table\n            .get(key)',
    1,
)

path.write_text(text)
