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
  --platforms=android,ios,macos,linux,windows \
  "$tmp/dxtr_box"

for platform in android ios macos linux windows; do
  rm -rf "$root/$platform"
  cp -R "$tmp/dxtr_box/$platform" "$root/$platform"
done

cd "$root"
# flutter_rust_bridge_codegen 2.8 uses Cargokit as the default integration
# backend and does not accept the newer --integration-backend option.
flutter_rust_bridge_codegen integrate
flutter_rust_bridge_codegen generate
