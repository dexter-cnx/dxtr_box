from pathlib import Path

path = Path("rust/src/api.rs")
text = path.read_text()

old_head = "        return index::list(&db).map(|definitions| {"
new_head = "        index::list(&db).map(|definitions| {"
if text.count(old_head) != 1:
    raise SystemExit(f"expected exactly one list_indexes head, got {text.count(old_head)}")
text = text.replace(old_head, new_head, 1)

marker = 'pub fn list_indexes(box_name: String) -> Result<Vec<NativeIndexDefinition>, String> {'
start = text.find(marker)
if start < 0:
    raise SystemExit("list_indexes function not found")
end_marker = '\npub fn drop_index('
end = text.find(end_marker, start)
if end < 0:
    raise SystemExit("drop_index boundary not found")

block = text[start:end]
old_tail = "                .collect()\n        });"
new_tail = "                .collect()\n        })"
if block.count(old_tail) != 1:
    raise SystemExit(f"expected exactly one list_indexes tail, got {block.count(old_tail)}")
block = block.replace(old_tail, new_tail, 1)
text = text[:start] + block + text[end:]

path.write_text(text)
