#!/usr/bin/env bash
# Apply PiliPlus' vendored SDK/package patches to the project-local toolchain.
# Safe to re-run: already-applied patches are skipped.
set -euo pipefail

PROJECT_ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)"
source "$PROJECT_ROOT/.tooling/env.sh"

apply_patch() {
  local dir="$1" patch="$2"
  local name
  name="$(basename "$patch")"
  if (cd "$dir" && git apply --check "$patch" >/dev/null 2>&1); then
    (cd "$dir" && git apply "$patch")
    echo "applied  $name"
  elif (cd "$dir" && git apply --reverse --check "$patch" >/dev/null 2>&1); then
    echo "skipped  $name (already applied)"
  else
    echo "FAILED   $name" >&2
    return 1
  fi
}

# Packages from the pub cache are not separate git repositories. Running
# `git apply` there targets the parent project's work tree, so use GNU patch
# which resolves paths relative to the current directory.
apply_plain_patch() {
  local dir="$1" patch="$2"
  local name
  name="$(basename "$patch")"
  if (cd "$dir" && patch -p1 --dry-run --forward < "$patch" >/dev/null 2>&1); then
    (cd "$dir" && patch -p1 --forward < "$patch" >/dev/null)
    echo "applied  $name"
  elif (cd "$dir" && patch -p1 --dry-run --reverse < "$patch" >/dev/null 2>&1); then
    echo "skipped  $name (already applied)"
  else
    echo "FAILED   $name" >&2
    return 1
  fi
}

FLUTTER_PATCHES=(
  modal_barrier
  text_selection
  mouse_cursor
  image_anim
  layout_builder
  navigation_drawer
  popup_menu
  fab
  null_safety_for_selectable_region
  selectable_region
  editable_text
  text_field
  scroll_position
  scrollable
  scrollable_gesture
  draggable_scrollable_sheet
  scaffold
  text
  text_painter
  sliver
  refresh_indicator
  double_tap_gesture
  scroll_view
  navigator
)

echo "Flutter SDK: $FLUTTER_ROOT"
for name in "${FLUTTER_PATCHES[@]}"; do
  apply_patch "$FLUTTER_ROOT" "$PROJECT_ROOT/lib/scripts/$name.patch"
done

MATERIAL_DIR="$(find "$PUB_CACHE/hosted" -maxdepth 2 -type d -name 'material_ui-*' 2>/dev/null | sort | tail -1)"
if [[ -z "$MATERIAL_DIR" ]]; then
  echo "material_ui package not found in $PUB_CACHE; run flutter pub get first" >&2
  exit 1
fi
echo "material_ui: $MATERIAL_DIR"
for name in modal_barrier_material navigation_drawer popup_menu fab text_field scaffold refresh_indicator tabs; do
  apply_plain_patch "$MATERIAL_DIR" "$PROJECT_ROOT/lib/scripts/material/$name.patch"
done

echo "All patches ready."
