#!/bin/sh
# Prepares MPVKit's prebuilt frameworks for App Store distribution. Runs as a
# post-build phase (see project.yml).
#
# - MinimumOSVersion: the frameworks declare 100.0, which App Store Connect
#   rejects; set it to the app's deployment target.
# - Signatures: the frameworks carry a vendor signature whose designated
#   requirement names "arm64-apple" instead of the bundle identifier. Re-signing
#   must not preserve it, or App Store Connect fails the upload (ITMS-90035).
#   Signed builds re-sign here; unsigned archives drop the old signature so the
#   export step signs the frameworks from scratch.
set -eu

FRAMEWORKS_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
[ -d "$FRAMEWORKS_DIR" ] || exit 0

for framework in "$FRAMEWORKS_DIR"/*.framework; do
  plist="$framework/Info.plist"
  [ -f "$plist" ] || continue
  /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion ${TVOS_DEPLOYMENT_TARGET}" "$plist"
  if [ "${CODE_SIGNING_ALLOWED:-YES}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$framework"
  else
    codesign --remove-signature "$framework"
  fi
done
