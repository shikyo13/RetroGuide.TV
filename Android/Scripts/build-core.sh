#!/usr/bin/env bash
# Builds the Swift core (Android/core) for Android and copies it, with the Swift
# runtime libraries it links, into app/src/main/jniLibs.
#
# Requires the swift.org toolchain and Swift SDK for Android of the same version,
# and the Android NDK. Override with SWIFT_TOOLCHAIN, SWIFT_SDK and ANDROID_NDK_HOME.
#   Scripts/build-core.sh [debug|release] [ABI…]
# ABIs default to arm64-v8a (devices and the arm64 emulator); release builds pass
# arm64-v8a armeabi-v7a x86_64. The app packages exactly the ABIs built here.
set -euo pipefail

ANDROID_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
shift || true
REQUESTED=("${@:-arm64-v8a}")
SWIFT_VERSION="6.4.1"
SWIFT_TOOLCHAIN="${SWIFT_TOOLCHAIN:-$HOME/Library/Developer/Toolchains/swift-$SWIFT_VERSION-RELEASE.xctoolchain}"
SWIFT_SDK="${SWIFT_SDK:-swift-$SWIFT_VERSION-RELEASE_android}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$(ls -d "$HOME"/Library/Android/sdk/ndk/* | sort -V | tail -1)}"
export ANDROID_NDK_HOME
API_LEVEL=28
# Android ABI → Swift target architecture and the NDK's name for it.
abi_entry() {
  case "$1" in
    arm64-v8a) echo "arm64-v8a:aarch64:aarch64-linux-android" ;;
    armeabi-v7a) echo "armeabi-v7a:armv7:arm-linux-androideabi" ;;
    x86_64) echo "x86_64:x86_64:x86_64-linux-android" ;;
    *) echo "unknown ABI $1" >&2; exit 1 ;;
  esac
}
# Remove ABIs that aren't being built, so the app never ships one without the core.
for existing in "$ANDROID_DIR"/app/src/main/jniLibs/*; do
  [[ -d "$existing" ]] || continue
  [[ " ${REQUESTED[*]} " == *" $(basename "$existing") "* ]] || rm -rf "$existing"
done

READELF="$(ls "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/llvm-readelf | head -1)"
STRIP="$(ls "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/llvm-strip | head -1)"

for requested in "${REQUESTED[@]}"; do
  IFS=: read -r ABI ARCH NDK_ARCH <<< "$(abi_entry "$requested")"
  TRIPLE="$ARCH-unknown-linux-android$API_LEVEL"
  echo "▸ $ABI: building RetroGuideCore ($CONFIGURATION)"
  "$SWIFT_TOOLCHAIN/usr/bin/swift" build --package-path "$ANDROID_DIR/core" -c "$CONFIGURATION" \
    --swift-sdk "$SWIFT_SDK" --triple "$TRIPLE" --product RetroGuideCore 2>&1 | grep -E "error|warning: |Build complete" || true
  PRODUCT="$ANDROID_DIR/core/.build/out/Products/${CONFIGURATION^}-android-$ARCH/libRetroGuideCore.so"
  [[ -e "$PRODUCT" ]] || { echo "$PRODUCT not found"; exit 1; }
  RUNTIME="$("$SWIFT_TOOLCHAIN/usr/bin/swift" sdk configure --show-configuration "$SWIFT_SDK" "$TRIPLE" 2>/dev/null \
    | sed -n 's/^swiftResourcesPath: //p' | head -1)/android"
  CXX_SHARED=$(find "$ANDROID_NDK_HOME" -path "*/$NDK_ARCH/libc++_shared.so" | head -1)

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
  # Debug symbols are about 40% of the runtime; crash reports symbolicate from the build.
  for lib in "$OUT"/*.so; do "$STRIP" --strip-unneeded "$lib"; done
  du -sh "$OUT" | sed "s|$ANDROID_DIR/||"
done
