pub mod api;
mod codec;
mod core;
#[cfg(feature = "encryption")]
pub mod crypto;
// The minimal/encryption-only profiles compile mutation paths without the
// full index-maintenance blocks, so bindings used exclusively by those
// cfg-gated blocks are intentionally unused there.
#[cfg_attr(not(feature = "full"), allow(unused_variables))]
mod db;
mod error;
mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. */
pub mod inspector;
#[cfg(feature = "full")]
mod index;
#[cfg(feature = "full")]
mod index_token;
#[cfg(all(test, feature = "full"))]
mod multi_frontend_bench;
pub mod native;
#[cfg(feature = "full")]
mod query;
#[cfg(all(test, feature = "full"))]
mod read_boundary_matrix_bench;
#[cfg(test)]
mod read_path_bench;
#[cfg(all(test, feature = "full"))]
mod real_world_bench;

pub use api::*;
pub use error::DxtrBoxError;
pub use native::{BoxHandle, DxtrBox, IndexDefinition, Record};
#[cfg(feature = "full")]
pub use native::{QueryBuilder, QueryValue, SortOrder};
