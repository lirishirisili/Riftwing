#!/usr/bin/env bash
# Build unsigned iOS Simulator .app from the Godot-exported Xcode project and
# package it for Appetize.io (PEND / Tohav pattern).
# Upload the .app (or the flat zip) — Appetize needs Something.app at the zip root.
#
# Official Godot iOS export templates ship simulator libgodot as x86_64 only
# (OSXCross cannot build arm64-simulator). Apple Silicon runners default to
# arm64 and then fail with undefined _main — force ARCHS=x86_64 for linking.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-env.sh
source "$SCRIPT_DIR/ci-env.sh"

: "${XCODE_PROJECT_ABS:?XCODE_PROJECT_ABS is required (Godot iOS export must have succeeded)}"

if [ ! -d "$XCODE_PROJECT_ABS" ]; then
  echo "ERROR: Xcode project not found at $XCODE_PROJECT_ABS" >&2
  ls -la "$(dirname "$XCODE_PROJECT_ABS")" || true
  exit 1
fi

ci_discover_xcode_scheme
: "${XCODE_SCHEME:?}"

SIMULATOR_DERIVED_DATA="${SIMULATOR_DERIVED_DATA:-$BUILD_DIR/DerivedDataSimulator}"
APPETIZE_STAGING_DIR="${APPETIZE_STAGING_DIR:-$BUILD_DIR/appetize-staging}"
APPETIZE_ZIP="${APPETIZE_ZIP:-$BUILD_DIR/${XCODE_SCHEME}-simulator-appetize.zip}"

echo "=== Build iOS Simulator app for Appetize (x86_64 — Godot template arch) ==="
# Do not require a runnable local simulator; we only need a linked .app for Appetize.
xcodebuild build \
  -project "$XCODE_PROJECT_ABS" \
  -scheme "$XCODE_SCHEME" \
  -configuration Release \
  -sdk iphonesimulator \
  -derivedDataPath "$SIMULATOR_DERIVED_DATA" \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  ARCHS=x86_64 \
  ONLY_ACTIVE_ARCH=YES \
  EXCLUDED_ARCHS=arm64 \
  COMPILER_INDEX_STORE_ENABLE=NO

APP_PATH=$(
  find "$SIMULATOR_DERIVED_DATA/Build/Products" -type d -name "${XCODE_SCHEME}.app" -path "*iphonesimulator*" 2>/dev/null \
    | head -1
)
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  APP_PATH=$(
    find "$SIMULATOR_DERIVED_DATA/Build/Products" -type d -name '*.app' -path '*iphonesimulator*' 2>/dev/null \
      | head -1
  )
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "ERROR: Could not find a .app under Simulator build products" >&2
  find "$SIMULATOR_DERIVED_DATA" -name "*.app" 2>/dev/null | head -20 >&2 || true
  exit 1
fi

APP_NAME=$(basename "$APP_PATH")
echo "Simulator app: $APP_PATH"
file "$APP_PATH/$APP_NAME" 2>/dev/null || file "$APP_PATH"/* 2>/dev/null | head -5 || true

rm -rf "$APPETIZE_STAGING_DIR"
mkdir -p "$APPETIZE_STAGING_DIR"
cp -R "$APP_PATH" "$APPETIZE_STAGING_DIR/"

STAGED_APP="$APPETIZE_STAGING_DIR/$APP_NAME"
export APPETIZE_APP_PATH="$STAGED_APP"

if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "APPETIZE_APP_PATH=$STAGED_APP"
    echo "APPETIZE_ZIP=$APPETIZE_ZIP"
  } >> "$GITHUB_ENV"
fi

rm -f "$APPETIZE_ZIP"
(
  cd "$APPETIZE_STAGING_DIR"
  zip -ry "$APPETIZE_ZIP" "$APP_NAME"
)
echo "Appetize zip: $APPETIZE_ZIP"
unzip -l "$APPETIZE_ZIP" | head -8 || true
if ! unzip -l "$APPETIZE_ZIP" | grep -q "${APP_NAME}/Info.plist"; then
  echo "ERROR: Zip does not contain ${APP_NAME}/Info.plist at root" >&2
  exit 1
fi

ls -la "$STAGED_APP"
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$STAGED_APP/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$STAGED_APP/Info.plist"
echo "=== Appetize package ready ==="
