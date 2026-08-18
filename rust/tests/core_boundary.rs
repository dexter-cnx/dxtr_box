#[test]
fn shared_core_has_no_frb_transport_dependency() {
    let source = include_str!("../src/core.rs");

    for forbidden in ["flutter_rust_bridge", "frb_generated", "StreamSink"] {
        assert!(
            !source.contains(forbidden),
            "shared core must not depend on FRB transport: found {forbidden}"
        );
    }
}

#[test]
fn frb_api_delegates_to_shared_core() {
    let source = include_str!("../src/api.rs");

    assert!(source.contains("use crate::{core, frb_generated::StreamSink};"));
    assert!(!source.contains("use crate::{db,"));
    assert!(!source.contains("use crate::{index,"));
}
