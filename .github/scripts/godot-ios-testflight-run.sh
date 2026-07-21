#!/usr/bin/env bash
# Godot 4.7 iOS: export Xcode project → sign → archive → IPA (TestFlight-ready).
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-env.sh
source "$SCRIPT_DIR/ci-env.sh"

RUN_PROBES="${RUN_PROBES:-false}"

bash "$SCRIPT_DIR/select-xcode-26.sh"
ci_install_cli_tools
ci_verify_asc_secrets
export APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_KEY_IDENTIFIER APP_STORE_CONNECT_PRIVATE_KEY

mkdir -p "$BUILD_DIR"

bash "$SCRIPT_DIR/install-godot-macos.sh"
: "${GODOT_BIN:?GODOT_BIN must be set by install-godot-macos.sh}"

if [ "$RUN_PROBES" = "true" ]; then
  echo "=== Run config probes ==="
  "$GODOT_BIN" --headless --path "$REPO_ROOT" --script res://tests/export_validation_probe.gd
  "$GODOT_BIN" --headless --path "$REPO_ROOT" --script res://tests/ads_service_probe.gd
else
  echo "=== Skipping probes (RUN_PROBES=false) ==="
fi

echo "=== Godot first import (bounded) ==="
set +e
"$GODOT_BIN" --headless --path "$REPO_ROOT" -e &
GODOT_IMPORT_PID=$!
sleep 90
kill "$GODOT_IMPORT_PID" 2>/dev/null || true
wait "$GODOT_IMPORT_PID" 2>/dev/null || true
set -e

echo "=== Godot iOS export (Xcode project) ==="
mkdir -p "$(dirname "$IOS_EXPORT_ABS")"
"$GODOT_BIN" --headless --path "$REPO_ROOT" --export-release "$IOS_EXPORT_PRESET" "$IOS_EXPORT_ABS"

if [ ! -d "$XCODE_PROJECT_ABS" ]; then
  echo "::error::Expected Xcode project at $XCODE_PROJECT_ABS after export." >&2
  ls -la "$(dirname "$XCODE_PROJECT_ABS")" || true
  exit 1
fi

MARKETING_VERSION="$(ci_read_marketing_version)"
echo "Marketing version: $MARKETING_VERSION, build: $BUILD_NUMBER"

ci_patch_exported_plist_versions() {
  local plist
  plist=$(find "$(dirname "$XCODE_PROJECT_ABS")" -name 'Info.plist' -not -path '*/Pods/*' 2>/dev/null | head -1)
  if [ -z "$plist" ]; then
    echo "::warning::No Info.plist found to patch versions; relying on export preset values."
    return 0
  fi
  echo "Patching $plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $MARKETING_VERSION" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$plist"
}

ci_patch_exported_plist_versions

fetch_signing_files() {
  keychain initialize
  openssl genrsa -out /tmp/certificate_key.pem 2048
  app-store-connect fetch-signing-files "$BUNDLE_ID" \
    --type IOS_APP_STORE \
    --create \
    --certificate-key @file:/tmp/certificate_key.pem \
    --verbose
  keychain add-certificates
  xcode-project use-profiles \
    --project "$XCODE_PROJECT_ABS" \
    --archive-method app-store \
    --export-options-plist "$HOME/export_options.plist" \
    --code-signing-setup-verbose-logging \
    --verbose
}

purge_distribution_certs() {
  echo "=== Purge Distribution certificates ==="
  set +o pipefail
  for CERT_TYPE in DISTRIBUTION IOS_DISTRIBUTION; do
    app-store-connect certificates list \
      --type "$CERT_TYPE" \
      --json 2>/dev/null \
      | jq -r '.[]?.id // empty' 2>/dev/null \
      | while read -r CERT_ID; do
          [ -z "$CERT_ID" ] && continue
          echo "Revoking $CERT_TYPE certificate: $CERT_ID"
          app-store-connect certificates delete "$CERT_ID" --ignore-not-found || true
        done
  done
  set -o pipefail
}

echo "=== Fetch & install code signing files ==="
mkdir -p "$(dirname "$HOME/export_options.plist")"
cp "$REPO_ROOT/ios/exportOptions.plist" "$HOME/export_options.plist"
purge_distribution_certs
fetch_signing_files

if ! grep -q 'PROVISIONING_PROFILE' "$XCODE_PROJECT_ABS/project.pbxproj"; then
  echo "::error::xcode-project use-profiles did not set PROVISIONING_PROFILE in the Xcode project." >&2
  ls -la "$HOME/Library/MobileDevice/Provisioning Profiles" 2>/dev/null || true
  ls -la "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" 2>/dev/null || true
  exit 1
fi

ci_discover_xcode_scheme

echo "=== Resolve Swift Package dependencies (AdMob) ==="
xcodebuild -resolvePackageDependencies \
  -project "$XCODE_PROJECT_ABS" \
  -scheme "$XCODE_SCHEME" \
  -derivedDataPath "$BUILD_DIR/DerivedData"

echo "=== Archive ==="
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_DIR/DerivedData}"
mkdir -p "$DERIVED_DATA_PATH"
set +e
xcodebuild archive \
  -project "$XCODE_PROJECT_ABS" \
  -scheme "$XCODE_SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$BUILD_DIR/build.xcarchive" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -jobs "$(sysctl -n hw.ncpu)" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$APPLE_DEVELOPMENT_TEAM" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  ONLY_ACTIVE_ARCH=NO \
  2>&1 | tee "$BUILD_DIR/xcodebuild-archive.log"
ARCHIVE_STATUS=${PIPESTATUS[0]}
set -e
if [ "$ARCHIVE_STATUS" -ne 0 ]; then
  echo "::error::xcodebuild archive failed with exit code $ARCHIVE_STATUS"
  grep -E 'error:|fatal error:|BUILD FAILED|Undefined symbols|clang: error|Swift Compiler Error|provisioning profile' \
    "$BUILD_DIR/xcodebuild-archive.log" | tail -n 80 || true
  tail -n 30 "$BUILD_DIR/xcodebuild-archive.log" || true
  exit "$ARCHIVE_STATUS"
fi

APP_PATH="$BUILD_DIR/build.xcarchive/Products/Applications/${XCODE_SCHEME}.app"
if [ ! -d "$APP_PATH" ]; then
  APP_PATH=$(find "$BUILD_DIR/build.xcarchive/Products/Applications" -maxdepth 1 -name '*.app' -type d | head -1)
fi
test -n "$APP_PATH"
test -d "$APP_PATH"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist"
echo "Archived app: $APP_PATH"

echo "=== Export IPA ==="
mkdir -p "$BUILD_DIR/ios/ipa"
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/build.xcarchive" \
  -exportPath "$BUILD_DIR/ios/ipa" \
  -exportOptionsPlist "$HOME/export_options.plist"

echo "=== iOS TestFlight pipeline finished ==="
ls -la "$BUILD_DIR/ios/ipa"/*.ipa
