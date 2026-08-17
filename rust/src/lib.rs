pub mod api;
mod codec;
#[cfg(feature = "encryption")]
pub mod crypto;
// The minimal/encryption-only profiles compile mutation paths without the
// full index-maintenance blocks, so bindings used exclusively by those
// cfg-gated blocks are intentionally unused there.
#[cfg_attr(not(feature = "full"), allow(unused_variables))]
mod db;
mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. */
#[cfg(feature = "full")]
mod index;
#[cfg(feature = "full")]
mod index_token;
#[cfg(feature = "full")]
mod query;
#[cfg(test)]
mod read_path_bench;

pub use api::*;
