#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${DXTR_BOX_MULTI_FRONTEND_OUTPUT_DIR:-${ROOT_DIR}/build/multi-frontend}"
RUST_ITERATIONS="${DXTR_BOX_MULTI_FRONTEND_RUST_ITERATIONS:-200}"
DART_ITERATIONS="${DXTR_BOX_MULTI_FRONTEND_DART_ITERATIONS:-200}"
SAMPLES="${DXTR_BOX_MULTI_FRONTEND_SAMPLES:-5}"
RECORDS="${DXTR_BOX_MULTI_FRONTEND_RECORDS:-1000}"
STARTUP_ITERATIONS="${DXTR_BOX_STARTUP_ITERATIONS:-100}"

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

cd "${ROOT_DIR}"
cargo build --manifest-path rust/Cargo.toml --release

DXTR_BOX_MULTI_FRONTEND_RUST_ITERATIONS="${RUST_ITERATIONS}" \
DXTR_BOX_MULTI_FRONTEND_RUST_SAMPLES="${SAMPLES}" \
DXTR_BOX_MULTI_FRONTEND_RECORDS="${RECORDS}" \
DXTR_BOX_MULTI_FRONTEND_RUST_OUTPUT="${OUTPUT_DIR}/rust-native.jsonl" \
cargo test --manifest-path rust/Cargo.toml --release \
  multi_frontend_bench::rust_native_frontend_benchmark -- --ignored --nocapture

LD_LIBRARY_PATH="rust/target/release:${LD_LIBRARY_PATH:-}" \
DYLD_LIBRARY_PATH="rust/target/release:${DYLD_LIBRARY_PATH:-}" \
PATH="rust/target/release:${PATH}" \
DXTR_BOX_MULTI_FRONTEND_BENCHMARK=1 \
DXTR_BOX_MULTI_FRONTEND_DART_ITERATIONS="${DART_ITERATIONS}" \
DXTR_BOX_MULTI_FRONTEND_DART_SAMPLES="${SAMPLES}" \
DXTR_BOX_MULTI_FRONTEND_RECORDS="${RECORDS}" \
DXTR_BOX_MULTI_FRONTEND_DART_OUTPUT="${OUTPUT_DIR}/dart-frb.jsonl" \
flutter test test/multi_frontend_benchmark_test.dart --reporter expanded

DXTR_BOX_STARTUP_ITERATIONS="${STARTUP_ITERATIONS}" \
cargo run --manifest-path rust/Cargo.toml --release --example startup_benchmark --features full \
  | tee "${OUTPUT_DIR}/startup-open.jsonl"

test -s "${OUTPUT_DIR}/rust-native.jsonl"
test -s "${OUTPUT_DIR}/dart-frb.jsonl"
test -s "${OUTPUT_DIR}/startup-open.jsonl"
printf '0.8 multi-frontend + 0.9 startup benchmark evidence: %s\n' "${OUTPUT_DIR}"
