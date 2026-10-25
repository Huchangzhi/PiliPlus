#!/usr/bin/env bash
# Serve the built web client plus the stateless relay on localhost.
set -euo pipefail

PROJECT_ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)"
source "$PROJECT_ROOT/.tooling/env.sh"
cd "$PROJECT_ROOT/server"

export HOST="${HOST:-127.0.0.1}"
export PORT="${PORT:-8787}"
export LOG_REQUESTS="${LOG_REQUESTS:-0}"

exec node server.mjs
