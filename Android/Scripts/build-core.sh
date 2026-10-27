#!/usr/bin/env bash
# Builds the Swift core (Android/core) for Android and copies it, with the Swift
# runtime libraries it links, into app/src/main/jniLibs.
#
# Requires the swift.org toolchain and Swift SDK for Android of the same version,
# and the Android NDK. Override with SWIFT_TOOLCHAIN, SWIFT_SDK and ANDROID_NDK_HOME.
#   Scripts/build-core.sh [debug|release]
set -euo pipefail

ANDROID_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
SWIFT_VERSION="6.4.1"
SWIFT_TOOLCHAIN="${SWIFT_TOOLCHAIN:-$HOME/Library/Developer/Toolchains/swift-$SWIFT_VERSION-RELEASE.xctoolchain}"
SWIFT_SDK="${SWIFT_SDK:-swift-$SWIFT_VERSION-RELEASE_android}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$(ls -d "$HOME"/Library/Android/sdk/ndk/* | sort -V | tail -1)}"
export ANDROID_NDK_HOME
API_LEVEL=28
# Android ABI → Swift target architecture.
ABIS=("arm64-v8a:aarch64")

READELF="$(ls "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/llvm-readelf | head -1)"

for entry in "${ABIS[@]}"; do
  ABI="${entry%%:*}"; ARCH="${entry##*:}"
  TRIPLE="$ARCH-unknown-linux-android$API_LEVEL"
  echo "▸ $ABI: building RetroGuideCore ($CONFIGURATION)"
  "$SWIFT_TOOLCHAIN/usr/bin/swift" build --package-path "$ANDROID_DIR/core" -c "$CONFIGURATION" \
    --swift-sdk "$SWIFT_SDK" --triple "$TRIPLE" --product RetroGuideCore 2>&1 | grep -E "error|warning: |Build complete" || true
  PRODUCT=$(find "$ANDROID_DIR/core/.build" -path "*${ARCH}*" -name libRetroGuideCore.so -newer "$ANDROID_DIR/core/Package.swift" | head -1)
  [[ -n "$PRODUCT" ]] || { echo "libRetroGuideCore.so not found"; exit 1; }
  RUNTIME="$("$SWIFT_TOOLCHAIN/usr/bin/swift" sdk configure --show-configuration "$SWIFT_SDK" "$TRIPLE" 2>/dev/null \
    | sed -n 's/^swiftResourcesPath: //p' | head -1)/android"
  CXX_SHARED=$(find "$ANDROID_NDK_HOME" -path "*$ARCH-linux-android/libc++_shared.so" | head -1)

  OUT="$ANDROID_DIR/app/src/main/jniLibs/$ABI"
  rm -rf "$OUT"; mkdir -p "$OUT"
  cp "$PRODUCT" "$OUT/"
  # Copy each library the core needs, following their own dependencies.
  pending=(libRetroGuideCore.so)
  while ((${#pending[@]})); do
    lib="${pending[0]}"; pending=("${pending[@]:1}")
    for needed in $("$READELF" -d "$OUT/$lib" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
      [[ -e "$OUT/$needed" ]] && continue
      if [[ -e "$RUNTIME/$needed" ]]; then
        cp -L "$RUNTIME/$needed" "$OUT/"; pending+=("$needed")
      elif [[ "$needed" == libc++_shared.so ]]; then
        cp -L "$CXX_SHARED" "$OUT/"
      fi
    done
  done
  du -sh "$OUT" | sed "s|$ANDROID_DIR/||"
  ls "$OUT"
done
