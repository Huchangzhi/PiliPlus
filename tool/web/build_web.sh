#!/usr/bin/env bash
# Build the static web client with the project-local toolchain.
set -euo pipefail

PROJECT_ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)"
source "$PROJECT_ROOT/.tooling/env.sh"
cd "$PROJECT_ROOT"

flutter pub get
tool/web/apply_sdk_patches.sh
tool/web/patch_packages.sh

flutter build web --release --no-tree-shake-icons --no-wasm-dry-run --no-web-resources-cdn "$@"

echo
echo "Static output: $PROJECT_ROOT/build/web"
echo "Serve it with: node server/server.mjs"
