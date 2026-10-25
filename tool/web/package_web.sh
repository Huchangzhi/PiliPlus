#!/usr/bin/env bash
# Package build/web as a Cloudflare Pages upload (index.html at zip root).
#
#   tool/web/package_web.sh                    # use current build/web
#   REBUILD=1 tool/web/package_web.sh          # rebuild first
#   REBUILD=1 PILI_SERVER=https://api.example.com tool/web/package_web.sh
set -euo pipefail

PROJECT_ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)"
source "$PROJECT_ROOT/.tooling/env.sh"
cd "$PROJECT_ROOT"

if [[ "${REBUILD:-0}" == "1" ]]; then
  if [[ -n "${PILI_SERVER:-}" ]]; then
    tool/web/build_web.sh --dart-define="PILI_SERVER=$PILI_SERVER"
  else
    tool/web/build_web.sh
  fi
fi

[[ -f build/web/index.html ]] || {
  echo "build/web is missing; run REBUILD=1 $0" >&2
  exit 1
}

mkdir -p dist
out="$PROJECT_ROOT/dist/piliplus-web-cf-pages.zip"
rm -f "$out"
# -X drops extended attributes so the archive is reproducible enough.
(cd build/web && zip -qrX "$out" .)
echo "$out"
