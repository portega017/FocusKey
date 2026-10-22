#!/usr/bin/env bash
set -euo pipefail

project_file="FocusKey.xcodeproj/project.pbxproj"

grep -q 'explicitFileType = wrapper.app-extension' "$project_file"
grep -q 'productType = "com.apple.product-type.app-extension"' "$project_file"
grep -q 'isa = PBXTargetDependency;' "$project_file"
grep -q 'name = "Embed App Extensions";' "$project_file"
grep -q '<key>com.apple.developer.family-controls</key>' FocusKeyMonitor/FocusKeyMonitor.entitlements

if [[ -n "${BUILT_PRODUCTS_DIR:-}" ]]; then
    app_bundle="$(find "$BUILT_PRODUCTS_DIR" -type d -name FocusKey.app -print -quit)"
    test -d "$app_bundle/PlugIns/FocusKeyMonitor.appex"
fi
