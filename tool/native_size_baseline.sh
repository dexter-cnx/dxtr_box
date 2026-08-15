#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/rust/Cargo.toml"
OUT_DIR="${DXTR_BOX_SIZE_OUT_DIR:-$ROOT_DIR/build/native-size}"
RESULTS="$OUT_DIR/native-size-baseline.tsv"

mkdir -p "$OUT_DIR"

case "$(uname -s)" in
  Linux*) artifact_name="librust_lib_dxtr_box.so" ;;
  Darwin*) artifact_name="librust_lib_dxtr_box.dylib" ;;
  *)
    echo "native size harness currently supports Linux and macOS shell environments" >&2
    exit 2
    ;;
esac

build_profile() {
  local profile="$1"
  shift
  local target_dir="$OUT_DIR/$profile/target"

  CARGO_TARGET_DIR="$target_dir" cargo build \
    --manifest-path "$MANIFEST" \
    --release \
    "$@"

  local artifact="$target_dir/release/$artifact_name"
  if [[ ! -f "$artifact" ]]; then
    echo "missing native artifact for $profile: $artifact" >&2
    exit 3
  fi

  local bytes
  bytes="$(wc -c < "$artifact" | tr -d ' ')"
  printf '%s\t%s\t%s\n' "$profile" "$bytes" "$artifact" >> "$RESULTS"
}

: > "$RESULTS"
printf '# dxtr_box native binary size baseline\n' >> "$RESULTS"
printf '# git=%s\n' "$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)" >> "$RESULTS"
printf '# os=%s\n' "$(uname -s)" >> "$RESULTS"
printf '# arch=%s\n' "$(uname -m)" >> "$RESULTS"
printf '# rustc=%s\n' "$(rustc --version)" >> "$RESULTS"
printf '# cargo=%s\n' "$(cargo --version)" >> "$RESULTS"
printf 'profile\tbytes\tartifact\n' >> "$RESULTS"

build_profile minimal --no-default-features
build_profile encryption --no-default-features --features encryption
build_profile full

cat "$RESULTS"
