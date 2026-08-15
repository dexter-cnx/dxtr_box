#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNS="${DXTR_BOX_SIZE_RUNS:-3}"
OUT_DIR="${DXTR_BOX_SIZE_STABILITY_OUT_DIR:-$ROOT_DIR/build/native-size-stability}"
SUMMARY="$OUT_DIR/native-size-stability.tsv"

if ! [[ "$RUNS" =~ ^[1-9][0-9]*$ ]]; then
  echo "DXTR_BOX_SIZE_RUNS must be a positive integer" >&2
  exit 2
fi

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

profiles=(minimal encryption full)
for profile in "${profiles[@]}"; do
  values=()
  for run in $(seq 1 "$RUNS"); do
    run_dir="$OUT_DIR/$profile/run-$run"
    rm -rf "$run_dir"
    case "$profile" in
      minimal)
        DXTR_BOX_SIZE_OUT_DIR="$run_dir" bash "$ROOT_DIR/tool/native_size_baseline.sh" >/dev/null
        ;;
      encryption|full)
        # One baseline invocation builds all profiles; reuse only the requested row.
        DXTR_BOX_SIZE_OUT_DIR="$run_dir" bash "$ROOT_DIR/tool/native_size_baseline.sh" >/dev/null
        ;;
    esac
    bytes="$(awk -F '\t' -v p="$profile" '$1 == p {print $2}' "$run_dir/native-size-baseline.tsv")"
    if [[ -z "$bytes" ]]; then
      echo "missing $profile measurement in run $run" >&2
      exit 3
    fi
    values+=("$bytes")
  done

  min="${values[0]}"
  max="${values[0]}"
  for value in "${values[@]}"; do
    (( value < min )) && min="$value"
    (( value > max )) && max="$value"
  done
  spread=$((max - min))
  stable=true
  if (( spread != 0 )); then
    stable=false
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$profile" "$RUNS" "$min" "$max" "$spread" "$stable" >> "$SUMMARY"
done

cat "$SUMMARY"

if grep -q $'\tfalse$' "$SUMMARY"; then
  echo "native size is not reproducible within the same commit/toolchain" >&2
  exit 4
fi
