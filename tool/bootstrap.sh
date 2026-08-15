#!/usr/bin/env bash
set -euo pipefail

flutter pub get
flutter_rust_bridge_codegen generate
flutter test
cargo test --manifest-path rust/Cargo.toml
