#!/bin/sh
# MPVKit's prebuilt frameworks declare MinimumOSVersion = 100.0, which App Store
# Connect rejects. Rewrite it to the app's deployment target and re-sign each
# framework. Runs as a post-build phase (see project.yml).
set -eu

FRAMEWORKS_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
[ -d "$FRAMEWORKS_DIR" ] || exit 0

for framework in "$FRAMEWORKS_DIR"/*.framework; do
  plist="$framework/Info.plist"
  [ -f "$plist" ] || continue
  /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion ${TVOS_DEPLOYMENT_TARGET}" "$plist"
  if [ "${CODE_SIGNING_ALLOWED:-YES}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --preserve-metadata=identifier,flags "$framework"
  fi
done
