#!/usr/bin/env bash
# Godot 4.7 iOS: export Xcode project → unsigned Simulator .app for Appetize.
# No App Store Connect secrets, signing, archive, or TestFlight upload.
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-env.sh
source "$SCRIPT_DIR/ci-env.sh"

RUN_PROBES="${RUN_PROBES:-false}"

bash "$SCRIPT_DIR/select-xcode-26.sh"

mkdir -p "$BUILD_DIR"

# Must source (not bash) so GODOT_BIN export survives.
# shellcheck source=install-godot-macos.sh
source "$SCRIPT_DIR/install-godot-macos.sh"
GODOT_BIN="${GODOT_BIN:-$CI_GODOT_DIR/Godot.app/Contents/MacOS/Godot}"
export GODOT_BIN
if [ ! -x "$GODOT_BIN" ]; then
  echo "::error::Godot binary missing at $GODOT_BIN after install-godot-macos.sh" >&2
  exit 1
fi

if [ "$RUN_PROBES" = "true" ]; then
  echo "=== Run config probes ==="
  "$GODOT_BIN" --headless --path "$REPO_ROOT" --script res://tests/export_validation_probe.gd
  "$GODOT_BIN" --headless --path "$REPO_ROOT" --script res://tests/ads_service_probe.gd
else
  echo "=== Skipping probes (RUN_PROBES=false) ==="
fi

echo "=== Build / restore iOS LevelPlay Godot plugin ==="
bash "$SCRIPT_DIR/build-ios-levelplay-plugin.sh"

# Appetize does not upload to Apple — use marketing version + run number (no ASC query).
export MARKETING_VERSION="${MARKETING_VERSION:-$(ci_read_marketing_version)}"
export IOS_MARKETING_VERSION="$MARKETING_VERSION"
IDENTITY_CODE="$(ci_read_version_code)"
RUN_NUM="${GITHUB_RUN_NUMBER:-1}"
export BUILD_NUMBER="${BUILD_NUMBER:-$RUN_NUM}"
if [ "$BUILD_NUMBER" -lt "$IDENTITY_CODE" ]; then
  export BUILD_NUMBER="$IDENTITY_CODE"
fi
echo "Appetize marketing version: $MARKETING_VERSION, build: $BUILD_NUMBER"
if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "BUILD_NUMBER=$BUILD_NUMBER"
    echo "MARKETING_VERSION=$MARKETING_VERSION"
  } >> "$GITHUB_ENV"
fi

echo "=== Godot first import (bounded) ==="
set +e
"$GODOT_BIN" --headless --path "$REPO_ROOT" -e &
GODOT_IMPORT_PID=$!
sleep 90
kill "$GODOT_IMPORT_PID" 2>/dev/null || true
wait "$GODOT_IMPORT_PID" 2>/dev/null || true
set -e

echo "=== Godot iOS export (Xcode project only) ==="
ci_patch_export_presets_team_id
ci_patch_export_presets_ios_versions
mkdir -p "$(dirname "$IOS_EXPORT_ABS")"
"$GODOT_BIN" --headless --path "$REPO_ROOT" --export-release "$IOS_EXPORT_PRESET" "$IOS_EXPORT_ABS"

if [ ! -d "$XCODE_PROJECT_ABS" ]; then
  echo "::error::Expected Xcode project at $XCODE_PROJECT_ABS after export." >&2
  ls -la "$(dirname "$XCODE_PROJECT_ABS")" || true
  exit 1
fi

ci_patch_xcode_project_versions
ci_discover_xcode_scheme

echo "=== LevelPlay CocoaPods (IronSource + adapters) ==="
# shellcheck source=ios-levelplay-pods.sh
source "$SCRIPT_DIR/ios-levelplay-pods.sh"
ci_discover_xcode_scheme

echo "=== Package Simulator app for Appetize ==="
bash "$SCRIPT_DIR/ios-simulator-appetize.sh"

echo "=== Appetize-only pipeline finished ==="
