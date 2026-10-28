#!/usr/bin/env bash
# Project-local toolchain environment. Source this file before Flutter/Dart commands:
#   source .tooling/env.sh
# All toolchain state, caches and downloaded packages stay inside this repository.

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
export PROJECT_ROOT
export FLUTTER_ROOT="$PROJECT_ROOT/.tooling/flutter"
export PUB_CACHE="$PROJECT_ROOT/.tooling/pub-cache"
export NPM_CONFIG_CACHE="$PROJECT_ROOT/.tooling/npm-cache"
export PATH="$FLUTTER_ROOT/bin:$PUB_CACHE/bin:$PROJECT_ROOT/server/node_modules/.bin:$PATH"

# Chinese mirrors for Flutter SDK artifacts and Dart packages.
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

# Keep analytics and first-run prompts out of the way.
export FLUTTER_SUPPRESS_ANALYTICS=true
export CI=true

# Keep git-hosted pub dependencies on a reachable mirror without touching the
# user's global git configuration.
export GIT_CONFIG_GLOBAL="$PROJECT_ROOT/.tooling/gitconfig"
export GIT_TERMINAL_PROMPT=0
