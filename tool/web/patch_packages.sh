#!/usr/bin/env bash
# Patch pub-cache packages that are not web-safe but are needed by the app.
# Run after `flutter pub get`; safe to re-run.
set -euo pipefail

PROJECT_ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)"
source "$PROJECT_ROOT/.tooling/env.sh"

# catcher_2 (git dependency) imports dart:ffi for ABI reporting, which breaks
# web compilation. ABI info is irrelevant in the browser.
CATCHER_DIR="$(find "$PUB_CACHE/git" -maxdepth 1 -type d -name 'catcher_2-*' | head -1)"
if [[ -n "$CATCHER_DIR" ]]; then
  file="$CATCHER_DIR/lib/core/catcher_2.dart"
  if grep -q "^import 'dart:ffi';" "$file"; then
    sed -i "/^import 'dart:ffi';$/d" "$file"
    sed -i "s/'abi': Abi.current().toString(),/'abi': 'unknown',/" "$file"
    echo "patched  catcher_2 (removed dart:ffi)"
  else
    echo "skipped  catcher_2"
  fi
fi

# cached_network_image_ce (git dependency) uses a 64-bit FNV constant that
# cannot be represented exactly in JavaScript. Use a 32-bit hash instead.
CACHE_DIR="$(find "$PUB_CACHE/git" -maxdepth 1 -type d -name 'flutter_cached_network_image_ce-*' | head -1)"
if [[ -n "$CACHE_DIR" ]]; then
  file="$CACHE_DIR/cached_network_image/lib/src/cache/extension.dart"
  if grep -q "0xcbf29ce484222325" "$file"; then
    python3 - "$file" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = """  int get fnvHash {
    var hash = 0xcbf29ce484222325;

    var i = 0;
    while (i < length) {
      final codeUnit = codeUnitAt(i++);
      hash ^= codeUnit >> 8;
      hash *= 0x100000001b3;
      hash ^= codeUnit & 0xFF;
      hash *= 0x100000001b3;
    }

    return hash;
  }"""
new = """  int get fnvHash {
    var hash = 0x811c9dc5;

    var i = 0;
    while (i < length) {
      final codeUnit = codeUnitAt(i++);
      hash = (hash * 31 + (codeUnit >> 8)) & 0xFFFFFFFF;
      hash = (hash * 31 + (codeUnit & 0xFF)) & 0xFFFFFFFF;
    }

    return hash;
  }"""
if old not in s:
    raise SystemExit("cached_network_image hash block not found")
open(p, 'w').write(s.replace(old, new))
PY
    echo "patched  cached_network_image_ce (32-bit hash)"
  else
    echo "skipped  cached_network_image_ce"
  fi
fi

# media_kit_video's web surface must fill its viewport instead of using the
# intrinsic video size (Flutter cannot transform DOM platform views).
MEDIA_VIDEO_DIR="$(find "$PUB_CACHE/hosted" -maxdepth 2 -type d -name 'media_kit_video-*' | head -1)"
if [[ -n "$MEDIA_VIDEO_DIR" ]]; then
  python3 "$PROJECT_ROOT/tool/web/patch_media_video.py" "$MEDIA_VIDEO_DIR"
fi

# cached_network_image_ce (git dependency) has no web ImageLoader. Install a
# browser loader that can route images through the relay.
CACHED_IMG_DIR="$(find "$PUB_CACHE/git" -maxdepth 1 -type d -name 'flutter_cached_network_image_ce-*' | head -1)"
if [[ -n "$CACHED_IMG_DIR" ]]; then
  python3 "$PROJECT_ROOT/tool/web/patch_cached_image.py" \
    "$CACHED_IMG_DIR/cached_network_image/lib" "$PROJECT_ROOT"
fi

# GetX (git dependency) reads dart:io Platform in its native page transition,
# which throws on web. Guard it with kIsWeb.
GETX_DIR="$(find "$PUB_CACHE/git" -maxdepth 1 -type d -name 'getx-*' | head -1)"
if [[ -n "$GETX_DIR" ]]; then
  file="$GETX_DIR/lib/get_navigation/src/routes/get_transition_mixin.dart"
  if ! grep -q "if (!kIsWeb && (Platform.isIOS || Platform.isMacOS))" "$file"; then
    python3 - "$file" <<'PY2'
import sys
p = sys.argv[1]
s = open(p).read()
if "import 'package:flutter/foundation.dart' show kIsWeb;" not in s:
    s = s.replace("import 'dart:io' show Platform;",
                  "import 'dart:io' show Platform;\n\nimport 'package:flutter/foundation.dart' show kIsWeb;")
s = s.replace("if (Platform.isIOS || Platform.isMacOS) {",
              "if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {")
open(p, 'w').write(s)
PY2
    echo "patched  getx (web platform guard)"
  else
    echo "skipped  getx"
  fi
fi

echo "Package patches ready."
