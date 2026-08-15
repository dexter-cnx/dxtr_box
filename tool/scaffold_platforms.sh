#!/usr/bin/env bash
set -euo pipefail

command -v flutter >/dev/null || { echo "flutter is required" >&2; exit 1; }
command -v flutter_rust_bridge_codegen >/dev/null || {
  echo "flutter_rust_bridge_codegen 2.8.0 is required" >&2
  exit 1
}

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

flutter create --template=plugin_ffi \
  --org com.dxtr \
  --platforms=android,ios,macos,linux,windows \
  "$tmp/dxtr_box"

for platform in android ios macos linux windows; do
  rm -rf "$root/$platform"
  cp -R "$tmp/dxtr_box/$platform" "$root/$platform"
done

cd "$root"
# FRB 2.8 uses Cargokit as its default integration backend.
flutter_rust_bridge_codegen integrate

# `integrate` scaffolds a demo API/application. dxtr_box already owns its API
# and example, so remove only those generated demo files before codegen.
rm -rf "$root/rust/src/api"
rm -f "$root/lib/main.dart"
rm -rf "$root/integration_test" "$root/test_driver"

# Generate bindings from the real `crate::api` implementation in rust/src/api.rs.
flutter_rust_bridge_codegen generate
