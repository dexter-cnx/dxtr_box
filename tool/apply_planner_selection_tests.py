from pathlib import Path

index_path = Path('rust/src/index.rs')
text = index_path.read_text()
old = '''pub(crate) fn candidate_keys(
    read: &ReadTransaction,
    filter: &query::Filter,
) -> Result<Option<Vec<String>>, String> {
    let candidates = query::index_candidates(filter)?;
    if candidates.is_empty() {
        return Ok(None);
    }

    let definitions = list_in_read(read)?;
    let mut candidate_sets = Vec::<HashSet<String>>::new();
    for candidate in candidates {
        let Some((index_name, _)) = definitions
            .iter()
            .find(|(_, indexed_field)| *indexed_field == candidate.field)
        else {
            continue;
        };
        candidate_sets.push(
            lookup_candidate(read, index_name, &candidate)?
                .into_iter()
                .collect(),
        );
    }

    if candidate_sets.is_empty() {
        return Ok(None);
    }
'''
new = '''fn select_index_candidates(
    definitions: &[(String, String)],
    candidates: Vec<query::IndexCandidate>,
) -> Vec<(String, query::IndexCandidate)> {
    candidates
        .into_iter()
        .filter_map(|candidate| {
            definitions
                .iter()
                .filter(|(_, indexed_field)| *indexed_field == candidate.field)
                .min_by(|(left_name, _), (right_name, _)| left_name.cmp(right_name))
                .map(|(index_name, _)| (index_name.clone(), candidate))
        })
        .collect()
}

pub(crate) fn candidate_keys(
    read: &ReadTransaction,
    filter: &query::Filter,
) -> Result<Option<Vec<String>>, String> {
    let candidates = query::index_candidates(filter)?;
    if candidates.is_empty() {
        return Ok(None);
    }

    let definitions = list_in_read(read)?;
    let selections = select_index_candidates(&definitions, candidates);
    if selections.is_empty() {
        return Ok(None);
    }

    let mut candidate_sets = Vec::<HashSet<String>>::with_capacity(selections.len());
    for (index_name, candidate) in selections {
        candidate_sets.push(
            lookup_candidate(read, &index_name, &candidate)?
                .into_iter()
                .collect(),
        );
    }
'''
if old not in text:
    raise SystemExit('candidate_keys anchor not found')
text = text.replace(old, new, 1)
old_tests = '''#[cfg(test)]
mod tests {
    use super::{index_prefix, prefix_successor};
'''
new_tests = '''#[cfg(test)]
mod tests {
    use super::{index_prefix, prefix_successor, select_index_candidates};
    use crate::query::{CompareOp, IndexCandidate};

    fn candidate(field: &str) -> IndexCandidate {
        IndexCandidate {
            field: field.to_string(),
            op: CompareOp::Equal,
            value: vec![0],
            upper_value: None,
        }
    }

    fn selected_names(
        definitions: &[(&str, &str)],
        candidates: Vec<IndexCandidate>,
    ) -> Vec<String> {
        let definitions = definitions
            .iter()
            .map(|(name, field)| (name.to_string(), field.to_string()))
            .collect::<Vec<_>>();
        select_index_candidates(&definitions, candidates)
            .into_iter()
            .map(|(name, _)| name)
            .collect()
    }

    #[test]
    fn planner_selection_requires_exact_field_match() {
        assert_eq!(
            selected_names(&[("by-age", "profile.age")], vec![candidate("profile.age")]),
            vec!["by-age"]
        );
        assert!(selected_names(&[("by-age", "profile.age")], vec![candidate("age")]).is_empty());
    }

    #[test]
    fn planner_selection_keeps_usable_subset_of_and_candidates() {
        assert_eq!(
            selected_names(
                &[("by-status", "status")],
                vec![candidate("status"), candidate("profile.age")],
            ),
            vec!["by-status"]
        );
    }

    #[test]
    fn planner_selection_keeps_multiple_usable_and_indexes() {
        assert_eq!(
            selected_names(
                &[("by-age", "profile.age"), ("by-status", "status")],
                vec![candidate("status"), candidate("profile.age")],
            ),
            vec!["by-status", "by-age"]
        );
    }

    #[test]
    fn planner_selection_is_deterministic_for_duplicate_field_indexes() {
        assert_eq!(
            selected_names(
                &[("z-status", "status"), ("a-status", "status")],
                vec![candidate("status")],
            ),
            vec!["a-status"]
        );
    }

    #[test]
    fn planner_selection_with_no_candidates_requires_scan_fallback() {
        assert!(selected_names(&[("by-status", "status")], Vec::new()).is_empty());
    }
'''
if old_tests not in text:
    raise SystemExit('index tests anchor not found')
text = text.replace(old_tests, new_tests, 1)
index_path.write_text(text)

query_path = Path('rust/src/query.rs')
text = query_path.read_text()
anchor = '''    #[test]
    fn integer_comparisons_preserve_values_above_f64_exact_range() {
'''
insert = '''    #[test]
    fn planner_candidates_do_not_descend_into_or_groups() {
        let filter = Filter::Group {
            op: LogicalOp::Or,
            filters: vec![
                Filter::Comparison(Comparison {
                    field: "status".to_string(),
                    op: CompareOp::Equal,
                    value: Some(Value::from("active")),
                    upper_value: None,
                }),
                Filter::Comparison(Comparison {
                    field: "profile.age".to_string(),
                    op: CompareOp::GreaterThanOrEqual,
                    value: Some(Value::from(18_i64)),
                    upper_value: None,
                }),
            ],
        };

        assert!(index_candidates(&filter).unwrap().is_empty());
    }

    #[test]
    fn planner_candidates_keep_eligible_members_under_and() {
        let filter = Filter::Group {
            op: LogicalOp::And,
            filters: vec![
                Filter::Comparison(Comparison {
                    field: "status".to_string(),
                    op: CompareOp::Equal,
                    value: Some(Value::from("active")),
                    upper_value: None,
                }),
                Filter::Comparison(Comparison {
                    field: "status".to_string(),
                    op: CompareOp::NotEqual,
                    value: Some(Value::from("archived")),
                    upper_value: None,
                }),
            ],
        };

        let candidates = index_candidates(&filter).unwrap();
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].field, "status");
        assert!(matches!(candidates[0].op, CompareOp::Equal));
    }

'''
if anchor not in text:
    raise SystemExit('query tests anchor not found')
text = text.replace(anchor, insert + anchor, 1)
query_path.write_text(text)
