from pathlib import Path
import re

path = Path('rust/src/index.rs')
text = path.read_text()
text, count = re.subn(
    r'\nfn entry_value_prefix\(index_name: &str, scalar: &\[u8\]\) -> Vec<u8> \{.*?\n\}\n(?=\nfn decode_record_key)',
    '',
    text,
    count=1,
    flags=re.S,
)
assert count == 1, 'unused entry_value_prefix helper not found'
path.write_text(text)
