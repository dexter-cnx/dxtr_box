#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_REL="rust/Cargo.toml"
BASE_REF="${DXTR_BOX_SIZE_BASE_REF:-HEAD^}"
MAX_GROWTH_BYTES="${DXTR_BOX_SIZE_MAX_GROWTH_BYTES:-65536}"
MAX_GROWTH_PERCENT="${DXTR_BOX_SIZE_MAX_GROWTH_PERCENT:-3}"
OUT_DIR="${DXTR_BOX_SIZE_REGRESSION_OUT_DIR:-$ROOT_DIR/build/native-size-regression}"
SUMMARY="$OUT_DIR/native-size-regression.tsv"
BASE_WORKTREE="$OUT_DIR/base-worktree"
HEAD_WORKTREE="$OUT_DIR/head-worktree"

for value_name in MAX_GROWTH_BYTES MAX_GROWTH_PERCENT; do
  value="${!value_name}"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$value_name must be a non-negative integer" >&2
    exit 2
  fi
done

case "$(uname -s)" in
  Linux*) artifact_name="librust_lib_dxtr_box.so" ;;
  Darwin*) artifact_name="librust_lib_dxtr_box.dylib" ;;
  *)
    echo "native size regression harness currently supports Linux and macOS shell environments" >&2
    exit 2
    ;;
esac

if ! git -C "$ROOT_DIR" rev-parse --verify "${BASE_REF}^{commit}" >/dev/null 2>&1; then
  echo "cannot resolve DXTR_BOX_SIZE_BASE_REF=$BASE_REF; fetch the base commit before running this gate" >&2
  exit 2
fi

HEAD_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD)"
BASE_SHA="$(git -C "$ROOT_DIR" rev-parse "${BASE_REF}^{commit}")"

if [[ "$HEAD_SHA" == "$BASE_SHA" ]]; then
  echo "base and head resolve to the same commit: $HEAD_SHA" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
rm -rf "$BASE_WORKTREE" "$HEAD_WORKTREE" "$OUT_DIR/base" "$OUT_DIR/head"

git -C "$ROOT_DIR" worktree add --detach "$BASE_WORKTREE" "$BASE_SHA" >/dev/null
git -C "$ROOT_DIR" worktree add --detach "$HEAD_WORKTREE" "$HEAD_SHA" >/dev/null
cleanup() {
  git -C "$ROOT_DIR" worktree remove --force "$BASE_WORKTREE" >/dev/null 2>&1 || true
  git -C "$ROOT_DIR" worktree remove --force "$HEAD_WORKTREE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

build_profile() {
  local repo_root="$1"
  local label="$2"
  local profile="$3"
  local target_dir="$OUT_DIR/$label/$profile/target"
  local manifest="$repo_root/$MANIFEST_REL"

  case "$profile" in
    minimal)
      CARGO_TARGET_DIR="$target_dir" cargo build --manifest-path "$manifest" --release --no-default-features >/dev/null
      ;;
    encryption)
      CARGO_TARGET_DIR="$target_dir" cargo build --manifest-path "$manifest" --release --no-default-features --features encryption >/dev/null
      ;;
    full)
      CARGO_TARGET_DIR="$target_dir" cargo build --manifest-path "$manifest" --release >/dev/null
      ;;
    *)
      echo "unknown profile: $profile" >&2
      exit 3
      ;;
  esac

  local artifact="$target_dir/release/$artifact_name"
  if [[ ! -f "$artifact" ]]; then
    echo "missing $label/$profile artifact: $artifact" >&2
    exit 3
  fi

  wc -c < "$artifact" | tr -d ' '
}

: > "$SUMMARY"
printf '# dxtr_box cross-commit native size regression gate\n' >> "$SUMMARY"
printf '# base_git=%s\n' "$BASE_SHA" >> "$SUMMARY"
printf '# head_git=%s\n' "$HEAD_SHA" >> "$SUMMARY"
printf '# os=%s\n' "$(uname -s)" >> "$SUMMARY"
printf '# arch=%s\n' "$(uname -m)" >> "$SUMMARY"
printf '# rustc=%s\n' "$(rustc --version)" >> "$SUMMARY"
printf '# cargo=%s\n' "$(cargo --version)" >> "$SUMMARY"
printf '# max_growth_bytes=%s\n' "$MAX_GROWTH_BYTES" >> "$SUMMARY"
printf '# max_growth_percent=%s\n' "$MAX_GROWTH_PERCENT" >> "$SUMMARY"
printf 'profile\tbase_bytes\thead_bytes\tdelta_bytes\tallowed_growth_bytes\tgrowth_percent\tstatus\n' >> "$SUMMARY"

failed=0
for profile in minimal encryption full; do
  base_bytes="$(build_profile "$BASE_WORKTREE" base "$profile")"
  head_bytes="$(build_profile "$HEAD_WORKTREE" head "$profile")"
  delta=$((head_bytes - base_bytes))
  percent_allowance=$(((base_bytes * MAX_GROWTH_PERCENT + 99) / 100))
  allowed_growth="$MAX_GROWTH_BYTES"
  if (( percent_allowance > allowed_growth )); then
    allowed_growth="$percent_allowance"
  fi

  growth_percent="$(awk -v delta="$delta" -v base="$base_bytes" 'BEGIN { if (base == 0) print "0.000"; else printf "%.3f", (delta * 100.0) / base }')"
  status=pass
  if (( delta > allowed_growth )); then
    status=fail
    failed=1
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$profile" "$base_bytes" "$head_bytes" "$delta" "$allowed_growth" "$growth_percent" "$status" >> "$SUMMARY"
done

cat "$SUMMARY"

if (( failed != 0 )); then
  echo "native binary size regression exceeded the controlled cross-commit budget" >&2
  echo "If the growth is intentional, document the reason and adjust the policy explicitly rather than bypassing the gate." >&2
  exit 4
fi
