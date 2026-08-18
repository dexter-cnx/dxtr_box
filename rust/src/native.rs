use std::path::{Path, PathBuf};

use crate::{core, DxtrBoxError};

#[cfg(feature = "full")]
use crate::query::{
    CompareOp, Comparison, Filter, LogicalOp, NullOrder, QuerySpec, SortDirection, SortSpec,
};
#[cfg(feature = "full")]
use rmpv::Value;

pub type Result<T> = std::result::Result<T, DxtrBoxError>;

#[derive(Debug, Clone)]
pub struct DxtrBox {
    path: PathBuf,
}

impl DxtrBox {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref().to_path_buf();
        core::init(&path).map_err(DxtrBoxError::from)?;
        Ok(Self { path })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn box_(&self, name: impl Into<String>) -> Result<BoxHandle> {
        self.box_with_key(name, None::<String>)
    }

    pub fn box_with_key(
        &self,
        name: impl Into<String>,
        encryption_key: Option<impl Into<String>>,
    ) -> Result<BoxHandle> {
        let name = name.into();
        if name.is_empty() {
            return Err(DxtrBoxError::invalid_input("box name cannot be empty"));
        }
        let encryption_key = encryption_key.map(Into::into);
        core::open_box(&name, encryption_key.as_deref()).map_err(DxtrBoxError::from)?;
        Ok(BoxHandle { name })
    }

    pub fn box_exists(&self, name: &str) -> Result<bool> {
        core::box_exists(name).map_err(DxtrBoxError::from)
    }
}

#[derive(Debug, Clone)]
pub struct BoxHandle {
    name: String,
}

impl BoxHandle {
    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn put(&self, key: impl Into<String>, value: impl Into<Vec<u8>>) -> Result<()> {
        let key = key.into();
        validate_key(&key)?;
        core::put_with(&self.name, key, value.into(), |_| {}).map_err(DxtrBoxError::from)
    }

    pub fn put_all(&self, entries: Vec<(String, Vec<u8>)>) -> Result<()> {
        for (key, _) in &entries {
            validate_key(key)?;
        }
        core::put_all_with(&self.name, entries, |_| {}).map_err(DxtrBoxError::from)
    }

    pub fn get(&self, key: &str) -> Result<Option<Vec<u8>>> {
        validate_key(key)?;
        core::get(&self.name, key).map_err(DxtrBoxError::from)
    }

    pub fn contains_key(&self, key: &str) -> Result<bool> {
        validate_key(key)?;
        core::contains_key(&self.name, key).map_err(DxtrBoxError::from)
    }

    pub fn get_all(&self, keys: &[String]) -> Result<Vec<Record>> {
        for key in keys {
            validate_key(key)?;
        }
        core::get_all(&self.name, keys)
            .map(|records| {
                records
                    .into_iter()
                    .map(|record| Record {
                        key: record.key,
                        value: record.value,
                    })
                    .collect()
            })
            .map_err(DxtrBoxError::from)
    }

    pub fn delete(&self, key: impl Into<String>) -> Result<()> {
        let key = key.into();
        validate_key(&key)?;
        core::delete_with(&self.name, key, |_| {}).map_err(DxtrBoxError::from)
    }

    pub fn delete_all(&self, keys: &[String]) -> Result<Vec<String>> {
        for key in keys {
            validate_key(key)?;
        }
        core::delete_all_with(&self.name, keys, |_| {}).map_err(DxtrBoxError::from)
    }

    pub fn clear(&self) -> Result<()> {
        core::clear_with(&self.name, |_| {}).map_err(DxtrBoxError::from)
    }

    pub fn all_keys(&self) -> Result<Vec<String>> {
        core::all_keys(&self.name).map_err(DxtrBoxError::from)
    }

    pub fn len(&self) -> Result<u64> {
        core::len(&self.name).map_err(DxtrBoxError::from)
    }

    pub fn is_empty(&self) -> Result<bool> {
        self.len().map(|len| len == 0)
    }

    pub fn close(&self) -> Result<()> {
        core::close_box(&self.name).map_err(DxtrBoxError::from)
    }

    pub fn compact(&self) -> Result<bool> {
        core::compact(&self.name).map_err(DxtrBoxError::from)
    }

    pub fn create_index(&self, name: &str, field: &str) -> Result<()> {
        if name.is_empty() || field.is_empty() {
            return Err(DxtrBoxError::invalid_input(
                "index name and field cannot be empty",
            ));
        }
        core::create_index(&self.name, name, field).map_err(DxtrBoxError::from)
    }

    pub fn list_indexes(&self) -> Result<Vec<IndexDefinition>> {
        core::list_indexes(&self.name)
            .map(|definitions| {
                definitions
                    .into_iter()
                    .map(|definition| IndexDefinition {
                        name: definition.name,
                        field: definition.field,
                    })
                    .collect()
            })
            .map_err(DxtrBoxError::from)
    }

    pub fn drop_index(&self, name: &str) -> Result<bool> {
        core::drop_index(&self.name, name).map_err(DxtrBoxError::from)
    }

    #[cfg(feature = "full")]
    pub fn query(&self) -> QueryBuilder<'_> {
        QueryBuilder::new(self)
    }

    #[cfg(not(feature = "full"))]
    pub fn query(&self) -> Result<()> {
        Err(DxtrBoxError::unsupported(
            "full",
            "native query execution requires the full profile",
        ))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Record {
    pub key: String,
    pub value: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IndexDefinition {
    pub name: String,
    pub field: String,
}

#[cfg(feature = "full")]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortOrder {
    Ascending,
    Descending,
}

#[cfg(feature = "full")]
#[derive(Debug, Clone, PartialEq)]
pub enum QueryValue {
    Null,
    Bool(bool),
    I64(i64),
    U64(u64),
    F64(f64),
    String(String),
}

#[cfg(feature = "full")]
impl From<&str> for QueryValue {
    fn from(value: &str) -> Self {
        Self::String(value.to_string())
    }
}

#[cfg(feature = "full")]
impl From<String> for QueryValue {
    fn from(value: String) -> Self {
        Self::String(value)
    }
}

#[cfg(feature = "full")]
impl From<bool> for QueryValue {
    fn from(value: bool) -> Self {
        Self::Bool(value)
    }
}

#[cfg(feature = "full")]
macro_rules! impl_query_value_signed {
    ($($ty:ty),* $(,)?) => {
        $(impl From<$ty> for QueryValue {
            fn from(value: $ty) -> Self { Self::I64(value as i64) }
        })*
    };
}

#[cfg(feature = "full")]
macro_rules! impl_query_value_unsigned {
    ($($ty:ty),* $(,)?) => {
        $(impl From<$ty> for QueryValue {
            fn from(value: $ty) -> Self { Self::U64(value as u64) }
        })*
    };
}

#[cfg(feature = "full")]
impl_query_value_signed!(i8, i16, i32, i64, isize);
#[cfg(feature = "full")]
impl_query_value_unsigned!(u8, u16, u32, u64, usize);

#[cfg(feature = "full")]
impl From<f32> for QueryValue {
    fn from(value: f32) -> Self {
        Self::F64(value as f64)
    }
}

#[cfg(feature = "full")]
impl From<f64> for QueryValue {
    fn from(value: f64) -> Self {
        Self::F64(value)
    }
}

#[cfg(feature = "full")]
impl From<QueryValue> for Value {
    fn from(value: QueryValue) -> Self {
        match value {
            QueryValue::Null => Value::Nil,
            QueryValue::Bool(value) => Value::Boolean(value),
            QueryValue::I64(value) => Value::from(value),
            QueryValue::U64(value) => Value::from(value),
            QueryValue::F64(value) => Value::from(value),
            QueryValue::String(value) => Value::from(value),
        }
    }
}

#[cfg(feature = "full")]
pub struct QueryBuilder<'a> {
    box_handle: &'a BoxHandle,
    filters: Vec<Filter>,
    sorts: Vec<SortSpec>,
    limit: Option<usize>,
    offset: usize,
}

#[cfg(feature = "full")]
impl<'a> QueryBuilder<'a> {
    fn new(box_handle: &'a BoxHandle) -> Self {
        Self {
            box_handle,
            filters: Vec::new(),
            sorts: Vec::new(),
            limit: None,
            offset: 0,
        }
    }

    pub fn where_(self, field: impl Into<String>) -> FieldPredicateBuilder<'a> {
        FieldPredicateBuilder {
            builder: self,
            field: field.into(),
        }
    }

    pub fn and(self, field: impl Into<String>) -> FieldPredicateBuilder<'a> {
        self.where_(field)
    }

    pub fn order_by(mut self, field: impl Into<String>, order: SortOrder) -> Self {
        self.sorts.push(SortSpec {
            field: field.into(),
            direction: match order {
                SortOrder::Ascending => SortDirection::Ascending,
                SortOrder::Descending => SortDirection::Descending,
            },
            nulls: NullOrder::Last,
        });
        self
    }

    pub fn limit(mut self, limit: usize) -> Result<Self> {
        if limit == 0 {
            return Err(DxtrBoxError::invalid_input(
                "query limit must be greater than 0",
            ));
        }
        self.limit = Some(limit);
        Ok(self)
    }

    pub fn offset(mut self, offset: usize) -> Self {
        self.offset = offset;
        self
    }

    pub fn find(self) -> Result<Vec<Record>> {
        let filter = match self.filters.len() {
            0 => {
                return Err(DxtrBoxError::invalid_input(
                    "query requires at least one predicate",
                ))
            }
            1 => self.filters.into_iter().next().expect("length checked"),
            _ => Filter::Group {
                op: LogicalOp::And,
                filters: self.filters,
            },
        };
        let spec = QuerySpec {
            filter,
            sort_by: self.sorts,
            limit: self.limit,
            offset: self.offset,
        };
        core::query(&self.box_handle.name, &spec)
            .map(|records| {
                records
                    .into_iter()
                    .map(|record| Record {
                        key: record.key,
                        value: record.value,
                    })
                    .collect()
            })
            .map_err(DxtrBoxError::from)
    }
}

#[cfg(feature = "full")]
pub struct FieldPredicateBuilder<'a> {
    builder: QueryBuilder<'a>,
    field: String,
}

#[cfg(feature = "full")]
impl<'a> FieldPredicateBuilder<'a> {
    pub fn equals(self, value: impl Into<QueryValue>) -> QueryBuilder<'a> {
        self.comparison(CompareOp::Equal, Some(value.into()), None)
    }

    pub fn not_equals(self, value: impl Into<QueryValue>) -> QueryBuilder<'a> {
        self.comparison(CompareOp::NotEqual, Some(value.into()), None)
    }

    pub fn greater_than(self, value: impl Into<QueryValue>) -> QueryBuilder<'a> {
        self.comparison(CompareOp::GreaterThan, Some(value.into()), None)
    }

    pub fn greater_than_or_equal(self, value: impl Into<QueryValue>) -> QueryBuilder<'a> {
        self.comparison(CompareOp::GreaterThanOrEqual, Some(value.into()), None)
    }

    pub fn less_than(self, value: impl Into<QueryValue>) -> QueryBuilder<'a> {
        self.comparison(CompareOp::LessThan, Some(value.into()), None)
    }

    pub fn less_than_or_equal(self, value: impl Into<QueryValue>) -> QueryBuilder<'a> {
        self.comparison(CompareOp::LessThanOrEqual, Some(value.into()), None)
    }

    pub fn between(
        self,
        lower: impl Into<QueryValue>,
        upper: impl Into<QueryValue>,
    ) -> QueryBuilder<'a> {
        self.comparison(CompareOp::Between, Some(lower.into()), Some(upper.into()))
    }

    pub fn is_null(self) -> QueryBuilder<'a> {
        self.comparison(CompareOp::IsNull, None, None)
    }

    pub fn is_not_null(self) -> QueryBuilder<'a> {
        self.comparison(CompareOp::IsNotNull, None, None)
    }

    fn comparison(
        mut self,
        op: CompareOp,
        value: Option<QueryValue>,
        upper_value: Option<QueryValue>,
    ) -> QueryBuilder<'a> {
        self.builder.filters.push(Filter::Comparison(Comparison {
            field: self.field,
            op,
            value: value.map(Value::from),
            upper_value: upper_value.map(Value::from),
        }));
        self.builder
    }
}

fn validate_key(key: &str) -> Result<()> {
    if key.is_empty() {
        return Err(DxtrBoxError::invalid_input("key cannot be empty"));
    }
    Ok(())
}
