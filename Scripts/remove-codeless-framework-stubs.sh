#!/bin/sh
# Removes the empty framework bundles Xcode embeds for MPVKit from an archive.
# Runs as the scheme's archive post-action (see project.yml), or by hand:
#   Scripts/remove-codeless-framework-stubs.sh path/to/RetroGuide.xcarchive
#
# MPVKit ships static libraries wrapped in .framework bundles. Their code is
# linked into the app executable, but Xcode still embeds each bundle and injects
# a placeholder binary built for the framework's declared MinimumOSVersion
# (100.0). App Store Connect rejects those placeholders (ITMS-90208, and
# ITMS-90035 for their signatures), and the app never loads them. They are
# harmless in development builds, so only archives are cleaned. Exporting the
# archive signs the app again.
#
# This runs after archiving rather than as a build phase because Xcode embeds
# package frameworks in steps a build phase can't be ordered after.
#
# A framework is removed only when the app executable doesn't link it and its
# binary exports no symbols, so real dynamic frameworks are always kept.
set -eu

ARCHIVE="${1:-${ARCHIVE_PATH:-}}"
[ -n "$ARCHIVE" ] || { echo "usage: $0 <archive.xcarchive>" >&2; exit 1; }

for app in "$ARCHIVE"/Products/Applications/*.app; do
  [ -d "$app/Frameworks" ] || continue
  executable="$app/$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$app/Info.plist")"
  linked_libraries=$(xcrun otool -L "$executable")

  for framework in "$app"/Frameworks/*.framework; do
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

  rmdir "$app/Frameworks" 2>/dev/null || true
done
