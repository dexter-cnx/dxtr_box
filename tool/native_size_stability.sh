#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/rust/Cargo.toml"
RUNS="${DXTR_BOX_SIZE_RUNS:-3}"
OUT_DIR="${DXTR_BOX_SIZE_STABILITY_OUT_DIR:-$ROOT_DIR/build/native-size-stability}"
SUMMARY="$OUT_DIR/native-size-stability.tsv"

if ! [[ "$RUNS" =~ ^[1-9][0-9]*$ ]]; then
  echo "DXTR_BOX_SIZE_RUNS must be a positive integer" >&2
  exit 2
fi

case "$(uname -s)" in
  Linux*) artifact_name="librust_lib_dxtr_box.so" ;;
  Darwin*) artifact_name="librust_lib_dxtr_box.dylib" ;;
  *)
    echo "native size stability harness currently supports Linux and macOS shell environments" >&2
    exit 2
    ;;
esac

mkdir -p "$OUT_DIR"
: > "$SUMMARY"
printf '# dxtr_box native size stability\n' >> "$SUMMARY"
printf '# git=%s\n' "$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)" >> "$SUMMARY"
printf '# os=%s\n' "$(uname -s)" >> "$SUMMARY"
printf '# arch=%s\n' "$(uname -m)" >> "$SUMMARY"
printf '# rustc=%s\n' "$(rustc --version)" >> "$SUMMARY"
printf '# cargo=%s\n' "$(cargo --version)" >> "$SUMMARY"
printf '# runs=%s\n' "$RUNS" >> "$SUMMARY"
printf 'profile\truns\tmin_bytes\tmax_bytes\tspread_bytes\tstable\n' >> "$SUMMARY"

build_profile() {
  local profile="$1"
  local target_dir="$2"
  case "$profile" in
    minimal)
      CARGO_TARGET_DIR="$target_dir" cargo build --manifest-path "$MANIFEST" --release --no-default-features
      ;;
    encryption)
      CARGO_TARGET_DIR="$target_dir" cargo build --manifest-path "$MANIFEST" --release --no-default-features --features encryption
      ;;
    full)
      CARGO_TARGET_DIR="$target_dir" cargo build --manifest-path "$MANIFEST" --release
      ;;
    *)
      echo "unknown profile: $profile" >&2
      exit 3
      ;;
  esac
}

for profile in minimal encryption full; do
  values=()
  for run in $(seq 1 "$RUNS"); do
    target_dir="$OUT_DIR/$profile/run-$run/target"
    rm -rf "$target_dir"
    build_profile "$profile" "$target_dir" >/dev/null
    artifact="$target_dir/release/$artifact_name"
    if [[ ! -f "$artifact" ]]; then
      echo "missing $profile artifact in run $run: $artifact" >&2
      exit 3
    fi
    values+=("$(wc -c < "$artifact" | tr -d ' ')")
  done

  min="${values[0]}"
  max="${values[0]}"
  for value in "${values[@]}"; do
    (( value < min )) && min="$value"
    (( value > max )) && max="$value"
  done
  spread=$((max - min))
  stable=true
  (( spread != 0 )) && stable=false
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$profile" "$RUNS" "$min" "$max" "$spread" "$stable" >> "$SUMMARY"
done

cat "$SUMMARY"

if grep -q $'\tfalse$' "$SUMMARY"; then
  echo "native size is not reproducible within the same commit/toolchain" >&2
  exit 4
fi
