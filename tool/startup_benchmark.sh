#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${DXTR_BOX_STARTUP_OUTPUT_DIR:-$ROOT_DIR/build/startup}"
OUTPUT_FILE="$OUTPUT_DIR/rust-startup.jsonl"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_FILE"

(
  cd "$ROOT_DIR/rust"
  cargo run --release --example startup_benchmark --features full
) | tee "$OUTPUT_FILE"

test -s "$OUTPUT_FILE"
