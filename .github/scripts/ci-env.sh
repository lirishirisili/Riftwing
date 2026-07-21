#!/usr/bin/env bash
# Shared CI environment for Riftwing GitHub Actions (Godot iOS → TestFlight).
set -euo pipefail

REPO_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export REPO_ROOT

export BUNDLE_ID="${BUNDLE_ID:-com.lishistudio.riftwing}"
export APPLE_DEVELOPMENT_TEAM="${APPLE_DEVELOPMENT_TEAM:-7BLH4NFZDD}"
export GODOT_VERSION="${GODOT_VERSION:-4.7-stable}"
export IOS_EXPORT_PRESET="${IOS_EXPORT_PRESET:-iOS}"
export IOS_EXPORT_PATH="${IOS_EXPORT_PATH:-build/ios/riftwing.ipa}"
export XCODE_PROJECT="${XCODE_PROJECT:-build/ios/riftwing.xcodeproj}"
# Default scheme matches Godot export basename; overridden after xcodebuild -list if needed.
export XCODE_SCHEME="${XCODE_SCHEME:-riftwing}"
export BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
export BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
export PRODUCT_IDENTITY="${PRODUCT_IDENTITY:-$REPO_ROOT/manifests/product_identity.json}"
export ASC_KEY_FILE="${ASC_KEY_FILE:-/tmp/AuthKey.p8}"

export CI_VENV="${CI_VENV:-$REPO_ROOT/.ci-venv}"
export CI_GODOT_DIR="${CI_GODOT_DIR:-$REPO_ROOT/.ci-godot}"
export GODOT_BIN="${GODOT_BIN:-$CI_GODOT_DIR/Godot.app/Contents/MacOS/Godot}"
export PATH="$CI_VENV/bin:$PATH"

ci_abs_path() {
  local p="$1"
  if [[ "$p" != /* ]]; then
    echo "$REPO_ROOT/$p"
  else
    echo "$p"
  fi
}

export XCODE_PROJECT_ABS="$(ci_abs_path "$XCODE_PROJECT")"
export IOS_EXPORT_ABS="$(ci_abs_path "$IOS_EXPORT_PATH")"

# Godot refuses iOS export when app_store_team_id is empty; git keeps "" for local honesty.
ci_patch_export_presets_team_id() {
  local team="${APPLE_DEVELOPMENT_TEAM:?APPLE_DEVELOPMENT_TEAM is required for Godot iOS export}"
  local cfg="$REPO_ROOT/export_presets.cfg"
  if grep -q "application/app_store_team_id=\"$team\"" "$cfg"; then
    echo "export_presets.cfg already has app_store_team_id=$team"
    return 0
  fi
  if ! grep -q 'application/app_store_team_id=""' "$cfg"; then
    echo "ERROR: export_presets.cfg app_store_team_id is not empty and not $team; refusing to patch." >&2
    exit 1
  fi
  sed -i.bak "s#application/app_store_team_id=\"\"#application/app_store_team_id=\"$team\"#" "$cfg"
  rm -f "$cfg.bak"
  echo "Patched export_presets.cfg app_store_team_id for CI Godot export."
}

ci_write_asc_key_file() {
  : "${APP_STORE_CONNECT_PRIVATE_KEY:?APP_STORE_CONNECT_PRIVATE_KEY is required}"
  printf '%s\n' "$APP_STORE_CONNECT_PRIVATE_KEY" > "$ASC_KEY_FILE"
}

ci_verify_asc_secrets() {
  for v in APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_KEY_IDENTIFIER APP_STORE_CONNECT_PRIVATE_KEY; do
    if [ -z "${!v:-}" ]; then
      echo "ERROR: $v is empty." >&2
      exit 1
    fi
  done
  ci_write_asc_key_file
  local key_lines
  key_lines=$(wc -l < "$ASC_KEY_FILE" | tr -d ' ')
  echo "Issuer ID length: ${#APP_STORE_CONNECT_ISSUER_ID}, Key ID: $APP_STORE_CONNECT_KEY_IDENTIFIER, .p8 lines: $key_lines"
  if [ "$key_lines" -lt 4 ]; then
    echo "ERROR: Private key looks like one line (broken paste)." >&2
    exit 1
  fi
  if ! grep -q 'BEGIN PRIVATE KEY' "$ASC_KEY_FILE"; then
    echo "ERROR: Missing -----BEGIN PRIVATE KEY----- in .p8 file." >&2
    exit 1
  fi
}

ci_install_cli_tools() {
  if [ -x "$CI_VENV/bin/app-store-connect" ]; then
    echo "Codemagic CLI tools already installed in $CI_VENV"
    return 0
  fi
  python3 -m venv "$CI_VENV"
  "$CI_VENV/bin/pip" install --upgrade pip
  "$CI_VENV/bin/pip" install codemagic-cli-tools
  command -v app-store-connect >/dev/null
  command -v keychain >/dev/null
  command -v xcode-project >/dev/null
  echo "Codemagic CLI tools installed."
}

ci_read_marketing_version() {
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
print(d.get('version_name', '0.1.0'))
" "$PRODUCT_IDENTITY"
}

ci_discover_xcode_scheme() {
  if [ ! -d "$XCODE_PROJECT_ABS" ]; then
    echo "ERROR: Xcode project not found: $XCODE_PROJECT_ABS" >&2
    exit 1
  fi
  local discovered=""
  if discovered=$(xcodebuild -list -project "$XCODE_PROJECT_ABS" -json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
schemes = data.get('project', {}).get('schemes', [])
if schemes:
    print(schemes[0])
" 2>/dev/null); then
    if [ -n "$discovered" ]; then
      export XCODE_SCHEME="$discovered"
      echo "Discovered Xcode scheme: $XCODE_SCHEME"
      return 0
    fi
  fi
  discovered=$(xcodebuild -list -project "$XCODE_PROJECT_ABS" 2>/dev/null | awk '/Schemes:/{flag=1;next} flag && NF{print $1; exit}')
  if [ -n "$discovered" ]; then
    export XCODE_SCHEME="$discovered"
    echo "Discovered Xcode scheme: $XCODE_SCHEME"
  else
    echo "Using default Xcode scheme: $XCODE_SCHEME"
  fi
}
