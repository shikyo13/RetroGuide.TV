#!/bin/sh
# Removes the empty framework bundles Xcode embeds for MPVKit. Runs as a
# post-build phase (see project.yml).
#
# MPVKit ships static libraries wrapped in .framework bundles. Their code is
# linked into the app executable, but Xcode still embeds each bundle and injects
# a placeholder binary built for the framework's declared MinimumOSVersion
# (100.0). App Store Connect rejects those placeholders (ITMS-90208, and
# ITMS-90035 for their signatures), and the app never loads them.
#
# A framework is removed only when the app executable doesn't link it and its
# binary exports no symbols, so real dynamic frameworks are always kept.
set -eu

FRAMEWORKS_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
EXECUTABLE="${TARGET_BUILD_DIR}/${EXECUTABLE_PATH}"
[ -d "$FRAMEWORKS_DIR" ] || exit 0

linked_libraries=$(xcrun otool -L "$EXECUTABLE")

for framework in "$FRAMEWORKS_DIR"/*.framework; do
  [ -d "$framework" ] || continue
  name=$(basename "$framework" .framework)
  binary="$framework/$name"

  case "$linked_libraries" in
    *"/$name.framework/"*) continue ;;
  esac
  if [ -f "$binary" ] && [ -n "$(xcrun nm -gU "$binary" 2>/dev/null)" ]; then
    continue
  fi

  echo "Removing codeless framework stub: $name.framework"
  rm -rf "$framework"
done

rmdir "$FRAMEWORKS_DIR" 2>/dev/null || true
