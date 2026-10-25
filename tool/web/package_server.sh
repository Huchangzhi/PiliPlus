#!/usr/bin/env bash
# Bundle the relay into a single Node ESM file and package it for deployment.
set -euo pipefail

PROJECT_ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)"
source "$PROJECT_ROOT/.tooling/env.sh"
cd "$PROJECT_ROOT/server"

npm install --no-audit --no-fund

out_dir="$PROJECT_ROOT/dist/server"
mkdir -p "$out_dir"
rm -f "$out_dir/pili-server.mjs"

./node_modules/.bin/esbuild server.mjs \
  --bundle \
  --platform=node \
  --target=node20 \
  --format=esm \
  --outfile="$out_dir/pili-server.mjs" \
  --external:bufferutil \
  --external:utf-8-validate \
  --legal-comments=none \
  --banner:js='import { createRequire as __createRequire } from "node:module"; const require = __createRequire(import.meta.url);'

cat > "$out_dir/.env.example" <<'EOF'
# Public deployment defaults. Copy to .env or pass as environment variables.
HOST=0.0.0.0
PORT=8787
ALLOW_ORIGIN=*

# Optional shared token (client sends x-pili-token).
# PROXY_TOKEN=

# Optional: serve the static client from the same process.
# STATIC_DIR=/app/web
EOF

cat > "$out_dir/Dockerfile" <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY pili-server.mjs ./
ENV HOST=0.0.0.0 PORT=8787
EXPOSE 8787
CMD ["node", "pili-server.mjs"]
EOF

cat > "$out_dir/README.txt" <<'EOF'
PiliPlus Web relay (single-file bundle)

Run directly (Node >= 20):
  HOST=0.0.0.0 PORT=8787 node pili-server.mjs

Docker:
  docker build -t piliplus-relay .
  docker run -d --name piliplus-relay -p 8787:8787 piliplus-relay

Health check:
  curl http://127.0.0.1:8787/health

The relay is stateless: accounts, cookies, history and cache stay in the
browser. It only forwards requests to allow-listed bilibili hosts and refuses
private/loopback targets (IPv4 and IPv6).

Point the static client at it by editing pili-config.js before deploying:
  window.PILI_SERVER = 'https://your-relay.example.com';

Optional environment variables: see .env.example.
EOF

out="$PROJECT_ROOT/dist/piliplus-server-node.zip"
rm -f "$out"
(cd "$out_dir" && zip -qrX "$out" .)
echo "$out"
