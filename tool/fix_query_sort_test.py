from pathlib import Path

path = Path('rust/tests/query_index.rs')
text = path.read_text()
old = '    let error = scan_query("mixed_sort".to_string(), payload).unwrap_err();\n    assert!(error.contains("mixes incompatible"));\n'
new = '    let error = match scan_query("mixed_sort".to_string(), payload) {\n        Ok(_) => panic!("mixed ordered sort types must be rejected"),\n        Err(error) => error,\n    };\n    assert!(error.contains("mixes incompatible"));\n'
if old not in text:
    raise SystemExit('mixed sort error assertion anchor not found')
path.write_text(text.replace(old, new, 1))
