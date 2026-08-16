#!/usr/bin/env bash
set -euo pipefail

command -v flutter >/dev/null || { echo "flutter is required" >&2; exit 1; }
command -v flutter_rust_bridge_codegen >/dev/null || {
  echo "flutter_rust_bridge_codegen 2.8.0 is required" >&2
  exit 1
}

root="$(cd "$(dirname "$0")/.." && pwd)"

cd "$root"
flutter pub get

# Native build ownership now lives in the root package. Keep the checked-in
# Cargokit integration and per-platform plugin files intact; this script only
# validates that topology and refreshes FRB bindings from the Rust crate.
required_paths=(
  "$root/cargokit"
  "$root/rust/Cargo.toml"
  "$root/android/build.gradle"
  "$root/ios/dxtr_box.podspec"
  "$root/macos/dxtr_box.podspec"
  "$root/linux/CMakeLists.txt"
  "$root/windows/CMakeLists.txt"
)

for required_path in "${required_paths[@]}"; do
  if [[ ! -e "$required_path" ]]; then
    echo "missing root plugin integration: ${required_path#$root/}" >&2
    exit 1
  fi
done

# Refresh bindings from the real `crate::api` implementation in rust/src/api.rs.
# FRB code generation should not need to re-run `integrate` for normal updates.
mkdir -p "$root/lib/src/rust"
flutter_rust_bridge_codegen generate
