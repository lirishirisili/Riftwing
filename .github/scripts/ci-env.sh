#!/usr/bin/env bash
# Shared CI environment for Riftwing (Godot iOS → TestFlight).
# Used by GitHub Actions and Codemagic (codemagic.yaml → ios-testflight).
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
# Codemagic: BUILD_DIR=$CM_BUILD_DIR so artifact globs resolve at clone root.
export BUILD_DIR="${BUILD_DIR:-${CM_BUILD_DIR:+$CM_BUILD_DIR}}"
export BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
# Codemagic sets BUILD_NUMBER from PROJECT_BUILD_NUMBER in codemagic.yaml.
if [ -n "${CM_BUILD_ID:-}" ]; then
  if [ -z "${BUILD_NUMBER:-}" ] || [ "${BUILD_NUMBER}" = "\$PROJECT_BUILD_NUMBER" ]; then
    BUILD_NUMBER="${PROJECT_BUILD_NUMBER:?PROJECT_BUILD_NUMBER or BUILD_NUMBER must be set on Codemagic}"
  fi
  export BUILD_NUMBER
  echo "Codemagic BUILD_NUMBER=$BUILD_NUMBER"
else
  export BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
fi
export PRODUCT_IDENTITY="${PRODUCT_IDENTITY:-$REPO_ROOT/manifests/product_identity.json}"
export ASC_KEY_FILE="${ASC_KEY_FILE:-/tmp/AuthKey.p8}"

export CI_VENV="${CI_VENV:-$REPO_ROOT/.ci-venv}"
export CI_GODOT_DIR="${CI_GODOT_DIR:-$REPO_ROOT/.ci-godot}"
export CI_GODOT_SRC="${CI_GODOT_SRC:-$REPO_ROOT/.ci-godot-src}"
export GODOT_BIN="${GODOT_BIN:-$CI_GODOT_DIR/Godot.app/Contents/MacOS/Godot}"
export PATH="$CI_VENV/bin:$PATH"
# Set by ios-levelplay-pods.sh after Godot export (optional).
export XCODE_WORKSPACE_ABS="${XCODE_WORKSPACE_ABS:-}"

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

ci_read_version_code() {
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
print(int(d.get('version_code', 1)))
" "$PRODUCT_IDENTITY"
}

# Godot iOS export copies application/version into CURRENT_PROJECT_VERSION. Patch the
# working copy only (never commit) so the generated Xcode project matches CI BUILD_NUMBER.
ci_patch_export_presets_ios_versions() {
  local cfg="$REPO_ROOT/export_presets.cfg"
  local ver="${BUILD_NUMBER:?BUILD_NUMBER is required to patch iOS application/version}"
  local marketing="${MARKETING_VERSION:-$(ci_read_marketing_version)}"
  python3 -c "
from pathlib import Path
cfg = Path('$cfg')
text = cfg.read_text()
import re
text, n_ver = re.subn(r'application/version=\"[^\"]*\"', 'application/version=\"$ver\"', text, count=1)
text, n_name = re.subn(r'application/short_version=\"[^\"]*\"', 'application/short_version=\"$marketing\"', text, count=1)
if n_ver != 1:
    raise SystemExit(f'expected to patch application/version once, patched {n_ver}')
if n_name != 1:
    raise SystemExit(f'expected to patch application/short_version once, patched {n_name}')
cfg.write_text(text)
print(f'Patched export_presets.cfg iOS application/version=$ver short_version=$marketing')
"
}

# Godot 4 iOS projects generate Info.plist from build settings (GENERATE_INFOPLIST_FILE).
# Patching Info.plist before archive does not stick — CURRENT_PROJECT_VERSION must change.
ci_patch_xcode_project_versions() {
  local pbx="$XCODE_PROJECT_ABS/project.pbxproj"
  local ver="${BUILD_NUMBER:?}"
  local marketing="${MARKETING_VERSION:-$(ci_read_marketing_version)}"
  if [ ! -f "$pbx" ]; then
    echo "::warning::No project.pbxproj at $pbx; relying on xcodebuild CURRENT_PROJECT_VERSION."
    return 0
  fi
  python3 -c "
from pathlib import Path
import re
pbx = Path('$pbx')
text = pbx.read_text()
text, n_ver = re.subn(r'CURRENT_PROJECT_VERSION = [^;]+;', 'CURRENT_PROJECT_VERSION = $ver;', text)
text, n_name = re.subn(r'MARKETING_VERSION = [^;]+;', 'MARKETING_VERSION = $marketing;', text)
pbx.write_text(text)
print('Patched pbxproj CURRENT_PROJECT_VERSION (%d) MARKETING_VERSION (%d) -> %s / %s' % (n_ver, n_name, '$ver', '$marketing'))
"
}

ci_discover_xcode_scheme() {
  if [ -n "${XCODE_WORKSPACE_ABS:-}" ] && [ -d "$XCODE_WORKSPACE_ABS" ]; then
    local discovered=""
    discovered=$(xcodebuild -list -workspace "$XCODE_WORKSPACE_ABS" -json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
schemes = data.get('workspace', {}).get('schemes', [])
# Prefer app scheme over Pods-* 
for s in schemes:
    if not str(s).startswith('Pods'):
        print(s)
        break
" 2>/dev/null || true)
    if [ -n "$discovered" ]; then
      export XCODE_SCHEME="$discovered"
      echo "Discovered Xcode scheme (workspace): $XCODE_SCHEME"
      if [ -n "${GITHUB_ENV:-}" ]; then
        echo "XCODE_SCHEME=$XCODE_SCHEME" >> "$GITHUB_ENV"
      fi
      return 0
    fi
  fi
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
      if [ -n "${GITHUB_ENV:-}" ]; then
        echo "XCODE_SCHEME=$XCODE_SCHEME" >> "$GITHUB_ENV"
      fi
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
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "XCODE_SCHEME=$XCODE_SCHEME" >> "$GITHUB_ENV"
  fi
}

# Args for xcodebuild that prefer CocoaPods workspace when present.
ci_xcode_container_args() {
  if [ -n "${XCODE_WORKSPACE_ABS:-}" ] && [ -d "$XCODE_WORKSPACE_ABS" ]; then
    echo "-workspace" "$XCODE_WORKSPACE_ABS"
  else
    echo "-project" "$XCODE_PROJECT_ABS"
  fi
}
