#!/usr/bin/env bash
# Install Godot editor (macOS universal) + export templates for headless iOS export.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-env.sh
source "$SCRIPT_DIR/ci-env.sh"

GODOT_ZIP="Godot_v${GODOT_VERSION}_macos.universal.zip"
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${GODOT_ZIP}"
TEMPLATES_TPZ="Godot_v${GODOT_VERSION}_export_templates.tpz"
TEMPLATES_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${TEMPLATES_TPZ}"

mkdir -p "$CI_GODOT_DIR"
TEMPLATES_DIR="$HOME/Library/Application Support/Godot/export_templates/4.7.stable"
mkdir -p "$TEMPLATES_DIR"

GODOT_APP="$CI_GODOT_DIR/Godot.app"
GODOT_BIN="$GODOT_APP/Contents/MacOS/Godot"

if [ ! -x "$GODOT_BIN" ]; then
  echo "=== Download Godot ${GODOT_VERSION} ==="
  curl -fsSL -o "$CI_GODOT_DIR/$GODOT_ZIP" "$GODOT_URL"
  unzip -q -o "$CI_GODOT_DIR/$GODOT_ZIP" -d "$CI_GODOT_DIR"
  rm -f "$CI_GODOT_DIR/$GODOT_ZIP"
fi

if [ ! -d "$TEMPLATES_DIR/ios" ] && [ ! -f "$TEMPLATES_DIR/version.txt" ]; then
  echo "=== Download Godot export templates ${GODOT_VERSION} ==="
  curl -fsSL -o "$CI_GODOT_DIR/$TEMPLATES_TPZ" "$TEMPLATES_URL"
  unzip -q -o "$CI_GODOT_DIR/$TEMPLATES_TPZ" -d "$CI_GODOT_DIR/templates_extract"
  # .tpz contains a top-level folder like templates/
  if [ -d "$CI_GODOT_DIR/templates_extract/templates" ]; then
    cp -R "$CI_GODOT_DIR/templates_extract/templates/"* "$TEMPLATES_DIR/"
  else
    cp -R "$CI_GODOT_DIR/templates_extract/"* "$TEMPLATES_DIR/"
  fi
  rm -rf "$CI_GODOT_DIR/templates_extract" "$CI_GODOT_DIR/$TEMPLATES_TPZ"
fi

test -x "$GODOT_BIN"
"$GODOT_BIN" --version
echo "Export templates dir: $TEMPLATES_DIR"
ls -la "$TEMPLATES_DIR" | head -20

export GODOT_BIN
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "GODOT_BIN=$GODOT_BIN" >> "$GITHUB_ENV"
fi
