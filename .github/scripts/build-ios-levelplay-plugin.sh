#!/usr/bin/env bash
# Build RiftstrikeLevelPlay Godot iOS plugin (.xcframework + .gdip) on macOS CI.
# Output under ios/plugins/ for Godot export to pick up.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-env.sh
source "$SCRIPT_DIR/ci-env.sh"

PLUGIN_SRC="$REPO_ROOT/native/levelplay/ios"
PLUGIN_DST="$REPO_ROOT/ios/plugins"
GODOT_TAG="${GODOT_SRC_TAG:-${GODOT_VERSION:-4.7-stable}}"
CI_GODOT_SRC="${CI_GODOT_SRC:-$REPO_ROOT/.ci-godot-src}"
CI_LP_BUILD="${CI_LP_BUILD:-$BUILD_DIR/levelplay-ios-plugin}"
CI_LP_PODS="${CI_LP_PODS:-$BUILD_DIR/levelplay-ios-pods}"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

export PATH="$HOME/Library/Python/3.13/bin:$HOME/Library/Python/3.12/bin:$HOME/Library/Python/3.11/bin:$HOME/.local/bin:$PATH"
if ! command -v scons >/dev/null 2>&1; then
  python3 -m pip install --user scons
fi
if ! command -v pod >/dev/null 2>&1; then
  gem install cocoapods --no-document
fi
command -v scons >/dev/null 2>&1
command -v pod >/dev/null 2>&1
command -v ruby >/dev/null 2>&1

mkdir -p "$PLUGIN_DST" "$CI_LP_BUILD" "$CI_LP_PODS"

if [ -f "$PLUGIN_DST/RiftstrikeLevelPlay.gdip" ] \
  && [ -d "$PLUGIN_DST/riftstrike_levelplay.release.xcframework" ]; then
  echo "=== LevelPlay iOS plugin already present (cache hit) — skipping rebuild ==="
  ls -la "$PLUGIN_DST"/RiftstrikeLevelPlay.gdip "$PLUGIN_DST"/riftstrike_levelplay.*.xcframework
  echo "LEVELPLAY_IOS_PLUGIN_OK"
  exit 0
fi

echo "=== Ensure Godot $GODOT_TAG source ==="
if [ ! -f "$CI_GODOT_SRC/core/object/object.h" ]; then
  rm -rf "$CI_GODOT_SRC"
  git clone --depth 1 --branch "$GODOT_TAG" https://github.com/godotengine/godot.git "$CI_GODOT_SRC"
fi

MARKER="$CI_GODOT_SRC/.riftwing_ios_headers_ready"
if [ ! -f "$MARKER" ]; then
  echo "=== Generate Godot iOS headers (scons; cached afterwards) ==="
  (
    cd "$CI_GODOT_SRC"
    scons platform=ios target=template_release arch=arm64 ios_simulator=no -j"$JOBS"
  )
  touch "$MARKER"
else
  echo "Using cached Godot headers at $CI_GODOT_SRC"
fi

echo "=== Fetch IronSourceSDK via CocoaPods (headers for compile) ==="
if [ ! -d "$CI_LP_PODS/Pods" ]; then
  rm -rf "$CI_LP_PODS"
  mkdir -p "$CI_LP_PODS"
  # Ruby xcodeproj ships with CocoaPods.
  ruby -rxcodeproj -e "
project = Xcodeproj::Project.new('$CI_LP_PODS/Headers.xcodeproj')
project.new_target(:application, 'LevelPlayHeaders', :ios, '15.0')
project.save
"
  cat > "$CI_LP_PODS/Podfile" <<'EOF'
platform :ios, '15.0'
use_frameworks! :linkage => :static
target 'LevelPlayHeaders' do
  pod 'IronSourceSDK', '9.5.0.0'
end
EOF
  (
    cd "$CI_LP_PODS"
    pod install --verbose
  )
fi

IRON_FRAMEWORK_DIR="$(find "$CI_LP_PODS/Pods" -type d -name 'IronSource.xcframework' 2>/dev/null | head -1 || true)"
if [ -z "$IRON_FRAMEWORK_DIR" ]; then
  echo "ERROR: IronSource.xcframework not found under $CI_LP_PODS/Pods" >&2
  find "$CI_LP_PODS/Pods" -maxdepth 4 -type d 2>/dev/null | head -40 >&2 || true
  exit 1
fi
IRON_INC="$(find "$IRON_FRAMEWORK_DIR" -type d -name 'Headers' 2>/dev/null | head -1 || true)"
IRON_FW_PARENT="$(dirname "$IRON_FRAMEWORK_DIR")"
echo "IronSource.xcframework=$IRON_FRAMEWORK_DIR"
echo "IronSource Headers=$IRON_INC"

compile_slice() {
  local sdk="$1"
  local arch="$2"
  local out_a="$3"
  local sdk_path
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  local min_flag
  if [ "$sdk" = "iphonesimulator" ]; then
    min_flag="-mios-simulator-version-min=15.0"
  else
    min_flag="-miphoneos-version-min=15.0"
  fi
  local obj="$CI_LP_BUILD/riftstrike_levelplay.${sdk}.${arch}.o"
  echo "Compiling $sdk/$arch"
  # shellcheck disable=SC2086
  clang++ -c "$PLUGIN_SRC/riftstrike_levelplay.mm" -o "$obj" \
    -arch "$arch" \
    -isysroot "$sdk_path" \
    $min_flag \
    -fobjc-arc -fmodules -fcxx-modules \
    -std=gnu++17 \
    -fvisibility=hidden \
    -fno-exceptions \
    -DIOS_ENABLED -DUNIX_ENABLED -DCOREAUDIO_ENABLED \
    -DVULKAN_ENABLED \
    -DNDEBUG -DNS_BLOCK_ASSERTIONS=1 \
    -DPTRCALL_ENABLED \
    -I"$CI_GODOT_SRC" \
    -I"$CI_GODOT_SRC/platform/ios" \
    ${IRON_INC:+-I"$IRON_INC"} \
    -F"$IRON_FW_PARENT" \
    -iframework "$sdk_path/System/Library/Frameworks"
  rm -f "$out_a"
  libtool -static -o "$out_a" "$obj"
}

echo "=== Compile plugin slices ==="
DEVICE_A="$CI_LP_BUILD/libriftstrike_levelplay.device.a"
SIM_X86_A="$CI_LP_BUILD/libriftstrike_levelplay.sim-x86_64.a"
SIM_ARM_A="$CI_LP_BUILD/libriftstrike_levelplay.sim-arm64.a"
SIM_FAT_A="$CI_LP_BUILD/libriftstrike_levelplay.simulator.a"

compile_slice iphoneos arm64 "$DEVICE_A"
compile_slice iphonesimulator x86_64 "$SIM_X86_A"
set +e
compile_slice iphonesimulator arm64 "$SIM_ARM_A"
SIM_ARM_STATUS=$?
set -e
if [ "$SIM_ARM_STATUS" -eq 0 ]; then
  lipo -create "$SIM_X86_A" "$SIM_ARM_A" -output "$SIM_FAT_A"
else
  echo "WARN: arm64-simulator compile failed; packaging x86_64 simulator only"
  cp "$SIM_X86_A" "$SIM_FAT_A"
fi

echo "=== Create xcframework ==="
XCF_RELEASE="$PLUGIN_DST/riftstrike_levelplay.release.xcframework"
XCF_DEBUG="$PLUGIN_DST/riftstrike_levelplay.debug.xcframework"
rm -rf "$XCF_RELEASE" "$XCF_DEBUG" "$PLUGIN_DST/riftstrike_levelplay.xcframework"
xcodebuild -create-xcframework \
  -library "$DEVICE_A" \
  -library "$SIM_FAT_A" \
  -output "$XCF_RELEASE"
cp -R "$XCF_RELEASE" "$XCF_DEBUG"

cp "$PLUGIN_SRC/RiftstrikeLevelPlay.gdip.template" "$PLUGIN_DST/RiftstrikeLevelPlay.gdip"

echo "=== Plugin ready ==="
ls -la "$PLUGIN_DST"/RiftstrikeLevelPlay.gdip "$PLUGIN_DST"/riftstrike_levelplay.*.xcframework
echo "LEVELPLAY_IOS_PLUGIN_OK"
