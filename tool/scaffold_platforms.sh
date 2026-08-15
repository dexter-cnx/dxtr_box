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

# Native build ownership lives exclusively in the checked-in Cargokit plugin.
# Do not recreate root android/ios/macos/linux/windows plugin_ffi scaffolds: the
# root package is the Dart-facing facade, while rust_builder/ owns native builds.
if [[ ! -d "$root/rust_builder" ]]; then
  echo "rust_builder/ is missing; restore the checked-in FRB/Cargokit integration" >&2
  exit 1
fi

# Refresh bindings from the real `crate::api` implementation in rust/src/api.rs.
# FRB code generation should not need to re-run `integrate` for normal updates.
mkdir -p "$root/lib/src/rust"
flutter_rust_bridge_codegen generate
