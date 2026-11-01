#!/bin/bash
# Testeinstieg: führt die Package-Tests auf dem iPhone-17-Simulator aus.
# Aufruf: ios/scripts/test.sh [Filter]   (Filter z. B. HaushaltsbuchCoreTests oder HaushaltsbuchCoreTests/MoneyTests)
# -skipPackagePluginValidation: das swift-openapi-generator-Build-Plugin (HaushaltsbuchAPI) würde
# sonst eine interaktive Freigabe in Xcode verlangen; ohne Flag bricht xcodebuild ab.
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/../HaushaltsbuchKit"
ARGS=()
if [ $# -gt 0 ]; then ARGS+=(-only-testing:"$1"); fi
xcodebuild test \
  -scheme HaushaltsbuchKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/Haushaltsbuch-Kit" \
  -skipPackagePluginValidation \
  ${ARGS[@]+"${ARGS[@]}"}
