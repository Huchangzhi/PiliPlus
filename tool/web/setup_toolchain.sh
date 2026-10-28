#!/usr/bin/env bash
# Restore the project-local web toolchain after it was deleted.
# Everything stays inside this repository; mirrors and versions are pinned so
# the result is the same as the first setup. Safe to run repeatedly.
#
#   tool/web/setup_toolchain.sh
#   FLUTTER_VERSION=3.47.7 tool/web/setup_toolchain.sh
set -euo pipefail

PROJECT_ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.7}"
FLUTTER_MIRROR="${FLUTTER_MIRROR:-https://storage.flutter-io.cn}"
cd "$PROJECT_ROOT"

# 1. toolchain config (never delete these templates; .tooling/ is gitignored)
mkdir -p .tooling
for name in env.sh gitconfig; do
  [[ -e ".tooling/$name" ]] || cp "tool/web/toolchain/$name" ".tooling/$name"
done
# shellcheck source=/dev/null
source .tooling/env.sh

# 2. Flutter SDK (tar.xz from the mirror, no git clone needed)
if [[ ! -x "$FLUTTER_ROOT/bin/flutter" ]]; then
  archive="$(curl -fsSL "$FLUTTER_MIRROR/flutter_infra_release/releases/releases_linux.json" \
    | FLUTTER_VERSION="$FLUTTER_VERSION" FLUTTER_MIRROR="$FLUTTER_MIRROR" python3 -c '
import json, os, sys
from urllib.parse import urlparse, urlunparse
data = json.load(sys.stdin)
want = os.environ["FLUTTER_VERSION"]
base = data["base_url"].rstrip("/")
mirror = urlparse(os.environ["FLUTTER_MIRROR"].rstrip("/"))
if mirror.netloc:
    parts = urlparse(base)
    base = urlunparse(
        (parts.scheme, mirror.netloc, parts.path, parts.params, "", "")
    ).rstrip("/")
for release in data["releases"]:
    if release["version"] == want and release["channel"] == "stable":
        print(base + "/" + release["archive"])
        break
else:
    sys.exit("flutter " + want + " not found on " + base)')"
  echo "fetching $archive"
  tmp="$(mktemp)"
  curl -fL --retry 3 -o "$tmp" "$archive"
  rm -rf "$FLUTTER_ROOT"
  tar -xJf "$tmp" -C .tooling
  rm -f "$tmp"
fi

# 3. engine artifacts, Dart packages, fork patches, server deps
flutter --disable-analytics >/dev/null
flutter precache --web
flutter pub get
tool/web/apply_sdk_patches.sh
tool/web/patch_packages.sh
(cd server && npm install --no-audit --no-fund)

echo
echo "ready: $(flutter --version | head -1)"
echo "build: REBUILD=1 tool/web/package_web.sh   # or tool/web/build_web.sh"
