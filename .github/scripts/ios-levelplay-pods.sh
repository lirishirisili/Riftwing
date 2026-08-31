#!/usr/bin/env bash
# After Godot iOS export: add LevelPlay CocoaPods and produce an .xcworkspace.
# Sets XCODE_WORKSPACE_ABS for subsequent xcodebuild archive/simulator builds.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-env.sh
source "$SCRIPT_DIR/ci-env.sh"

: "${XCODE_PROJECT_ABS:?}"
IOS_DIR="$(dirname "$XCODE_PROJECT_ABS")"
SCHEME_NAME="${XCODE_SCHEME:-riftwing}"

if ! command -v pod >/dev/null 2>&1; then
  gem install cocoapods --no-document
fi

echo "=== Write LevelPlay Podfile in $IOS_DIR ==="
cat > "$IOS_DIR/Podfile" <<EOF
platform :ios, '15.0'
use_frameworks! :linkage => :static

target '${SCHEME_NAME}' do
  pod 'IronSourceSDK', '9.5.0.0'
  pod 'IronSourceUnityAdsAdapter', '5.9.0.0'
  pod 'IronSourceFacebookAdapter', '5.4.0.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
    end
  end
end
EOF

(
  cd "$IOS_DIR"
  pod install --verbose
)

WORKSPACE="$IOS_DIR/${SCHEME_NAME}.xcworkspace"
if [ ! -d "$WORKSPACE" ]; then
  # CocoaPods names the workspace after the project basename.
  WORKSPACE="$(find "$IOS_DIR" -maxdepth 1 -name '*.xcworkspace' -type d | head -1 || true)"
fi
if [ -z "$WORKSPACE" ] || [ ! -d "$WORKSPACE" ]; then
  echo "ERROR: Expected CocoaPods xcworkspace under $IOS_DIR" >&2
  ls -la "$IOS_DIR" >&2 || true
  exit 1
fi

export XCODE_WORKSPACE_ABS="$WORKSPACE"
echo "XCODE_WORKSPACE_ABS=$XCODE_WORKSPACE_ABS"
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "XCODE_WORKSPACE_ABS=$XCODE_WORKSPACE_ABS" >> "$GITHUB_ENV"
fi
echo "LEVELPLAY_IOS_PODS_OK"
