#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

chmod +x .githooks/pre-push
git config core.hooksPath .githooks

echo "Installed dxtr_box Git hooks."
echo "pre-push will auto-format Dart/Rust sources and stop the push if formatting changes files."
