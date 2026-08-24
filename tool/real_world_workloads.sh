#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${DXTR_BOX_REAL_WORLD_OUTPUT_DIR:-$ROOT_DIR/build/real-world}"
CATALOG_RECORDS="${DXTR_BOX_REAL_WORLD_CATALOG:-1000}"
ACTIVITY_RECORDS="${DXTR_BOX_REAL_WORLD_ACTIVITY:-2000}"
SAMPLES="${DXTR_BOX_REAL_WORLD_SAMPLES:-5}"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

cd "$ROOT_DIR"
cargo build --manifest-path rust/Cargo.toml --release

DXTR_BOX_REAL_WORLD_CATALOG="$CATALOG_RECORDS" \
DXTR_BOX_REAL_WORLD_ACTIVITY="$ACTIVITY_RECORDS" \
DXTR_BOX_REAL_WORLD_SAMPLES="$SAMPLES" \
  cargo test --manifest-path rust/Cargo.toml --release \
    real_world_bench::rust_native_real_world_scenarios -- --ignored --nocapture \
  | tee "$OUTPUT_DIR/rust-native.log"

grep 'DXTR_BOX_REAL_WORLD_RUST ' "$OUTPUT_DIR/rust-native.log" \
  | sed 's/^.*DXTR_BOX_REAL_WORLD_RUST //' \
  > "$OUTPUT_DIR/rust-native.jsonl"

cd "$ROOT_DIR/benchmark"
flutter pub get

LD_LIBRARY_PATH="$ROOT_DIR/rust/target/release:${LD_LIBRARY_PATH:-}" \
DYLD_LIBRARY_PATH="$ROOT_DIR/rust/target/release:${DYLD_LIBRARY_PATH:-}" \
PATH="$ROOT_DIR/rust/target/release:$PATH" \
DXTR_BOX_REAL_WORLD=1 \
DXTR_BOX_REAL_WORLD_CATALOG="$CATALOG_RECORDS" \
DXTR_BOX_REAL_WORLD_ACTIVITY="$ACTIVITY_RECORDS" \
DXTR_BOX_REAL_WORLD_SAMPLES="$SAMPLES" \
DXTR_BOX_NATIVE_BUILD_MODE=release \
  flutter test test/real_world_dxtr_benchmark_test.dart --reporter expanded \
  | tee "$OUTPUT_DIR/dart-frb.log"

grep 'DXTR_BOX_REAL_WORLD ' "$OUTPUT_DIR/dart-frb.log" \
  | sed 's/^.*DXTR_BOX_REAL_WORLD //' \
  > "$OUTPUT_DIR/dart-frb.jsonl"

rust_lines="$(wc -l < "$OUTPUT_DIR/rust-native.jsonl" | tr -d ' ')"
dart_lines="$(wc -l < "$OUTPUT_DIR/dart-frb.jsonl" | tr -d ' ')"
test "$rust_lines" -eq 3
test "$dart_lines" -eq 3

{
  echo "generated_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "catalog_records=$CATALOG_RECORDS"
  echo "activity_records=$ACTIVITY_RECORDS"
  echo "samples=$SAMPLES"
  echo "rustc=$(rustc --version)"
  echo "cargo=$(cargo --version)"
  echo "flutter=$(flutter --version | head -n 1)"
  echo "dart=$(dart --version 2>&1)"
} > "$OUTPUT_DIR/toolchain.txt"

printf 'real-world evidence written to %s\n' "$OUTPUT_DIR"
