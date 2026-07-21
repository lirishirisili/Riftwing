#!/usr/bin/env bash
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-env.sh
source "$SCRIPT_DIR/ci-env.sh"

ci_install_cli_tools
ci_verify_asc_secrets

IPA=$(find "$BUILD_DIR/ios/ipa" -name '*.ipa' -print -quit)
test -n "$IPA"

echo "Publishing $IPA to TestFlight..."
app-store-connect publish \
  --path "$IPA" \
  --testflight \
  --issuer-id "$APP_STORE_CONNECT_ISSUER_ID" \
  --key-id "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
  --private-key "@file:${ASC_KEY_FILE}"

echo "TestFlight upload submitted."
