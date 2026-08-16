from pathlib import Path

sections = {
    'docs/CODE_WALKTHROUGH.md': '''\n\n## 19. Bounded persisted-index iteration\n\nPersisted-index candidate lookup no longer iterates the entire `index_entries` table. `rust/src/index.rs` computes the encoded index-name prefix and its lexicographic successor, then asks redb for only that half-open key range. `dropIndex` cleanup uses the same bounded range.\n\nThis optimization is deliberately limited to the **index-name component**. Scalar MessagePack bytes inside that range are still decoded and compared with the query engine comparator, so numeric/string query semantics are unchanged and raw MessagePack byte ordering is never treated as numeric ordering.\n\nA future scalar-level redb range seek still requires a proven order-preserving scalar encoding.\n''',
    'docs/QUERY_INDEX_03.md': '''\n\n## Bounded index-name range optimization\n\nPersisted index lookup and `dropIndex` cleanup now use a redb half-open range bounded by the encoded index-name prefix and its lexicographic successor. This skips unrelated persisted indexes at the storage iterator level while preserving the existing scalar comparison contract.\n\nThe optimization does **not** use MessagePack scalar bytes as numeric range bounds. Candidate scalar components are still decoded and evaluated with the same exact comparator used by the authoritative query engine. Scan/index equivalence therefore remains unchanged.\n''',
    'docs/PROJECT_HANDOFF.md': '''\n\n## Latest 0.3 optimization — bounded index-name iteration\n\n`feature/0.3-index-prefix-range` replaces whole-`index_entries` iteration for candidate lookup and index-drop cleanup with redb ranges bounded to one encoded index-name prefix. Public Dart/FRB APIs and planner eligibility do not change.\n\nImportant constraint: this is **not** scalar-order range seeking. MessagePack scalar components are still decoded and compared using the query engine comparator. Any future scalar-level seek requires an order-preserving encoding proven equivalent to query numeric/string semantics.\n\nAfter this slice, the next architecture candidate remains one-redb-read-transaction query execution, followed by explicit sort semantics and benchmark scenarios only after correctness remains stable.\n''',
    'README.md': '''\n\n### Persisted-index lookup optimization\n\nIndex-backed queries bound redb iteration to the selected persisted index name rather than scanning unrelated `index_entries`. Range predicates still decode stored MessagePack scalars and use the query comparator; raw MessagePack byte order is not used as numeric order.\n''',
}

for filename, section in sections.items():
    path = Path(filename)
    text = path.read_text()
    heading = section.strip().splitlines()[0]
    if heading not in text:
        path.write_text(text.rstrip() + section + '\n')
