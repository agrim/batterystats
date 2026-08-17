#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:-}"
APP_NAME="BatteryStats"
TEAM_ID="${BATTERYSTATS_TEAM_ID:-Q293G85PG5}"
APP_GROUP="${BATTERYSTATS_APP_GROUP:-$TEAM_ID.io.github.agrim.batterystats}"
EXPECTED_VERSION="${BATTERYSTATS_EXPECTED_MARKETING_VERSION:-1.0.4}"
EXPECTED_BUILD="${BATTERYSTATS_EXPECTED_BUILD_VERSION:-5}"
APP_BUNDLE_ID="io.github.agrim.batterystats"
WIDGET_BUNDLE_ID="io.github.agrim.batterystats.widgets"
REQUIRE_DEVELOPER_ID="${BATTERYSTATS_REQUIRE_DEVELOPER_ID:-0}"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
  fail "usage: $0 /path/to/BatteryStats.app"
fi

WIDGET_BUNDLE="$APP_BUNDLE/Contents/PlugIns/BatteryStatsWidgetsExtension.appex"
if [[ ! -d "$WIDGET_BUNDLE" ]]; then
  fail "missing embedded widget at $WIDGET_BUNDLE"
fi
if find "$APP_BUNDLE" -type d -name '*.xctest' -print -quit | grep -q .; then
  fail "signed app contains an embedded test bundle"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/batterystats-signing.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
APP_ENTITLEMENTS="$TMP_DIR/app-entitlements.plist"
WIDGET_ENTITLEMENTS="$TMP_DIR/widget-entitlements.plist"

plist_value() {
  local path="$1"
  local key="$2"
  plutil -extract "$key" raw -o - "$path" 2>/dev/null || true
}

extract_entitlements() {
  local bundle="$1"
  local output="$2"
  local executable_name
  local executable

  executable_name="$(bundle_value "$bundle" CFBundleExecutable)"
  executable="$bundle/Contents/MacOS/$executable_name"
  if [[ ! -x "$executable" ]]; then
    fail "missing signed executable at $executable"
  fi

  if command -v derq >/dev/null 2>&1; then
    local code_signing_blob="$output.csblob"
    derq macho --input "$executable" --xml --output "$code_signing_blob"
    if [[ "$(xxd -p -l 4 "$code_signing_blob")" != "fade7171" ]]; then
      fail "derq returned an unexpected entitlement blob for $bundle"
    fi
    dd if="$code_signing_blob" of="$output" bs=1 skip=8 status=none
  else
    codesign -d --entitlements :- "$bundle" >"$output" 2>/dev/null
  fi

  plutil -lint "$output" >/dev/null
}

bundle_value() {
  local bundle="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$bundle/Contents/Info.plist" 2>/dev/null || true
}

team_identifier() {
  codesign -dv --verbose=4 "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1
}

signed_architectures() {
  local bundle="$1"
  local executable_name
  executable_name="$(bundle_value "$bundle" CFBundleExecutable)"
  lipo -archs "$bundle/Contents/MacOS/$executable_name"
}

assert_equal() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "$actual" != "$expected" ]]; then
    fail "$label is '$actual'; expected '$expected'"
  fi
}

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$WIDGET_BUNDLE"
extract_entitlements "$APP_BUNDLE" "$APP_ENTITLEMENTS"
extract_entitlements "$WIDGET_BUNDLE" "$WIDGET_ENTITLEMENTS"

assert_equal "$(bundle_value "$APP_BUNDLE" CFBundleIdentifier)" "$APP_BUNDLE_ID" "app bundle identifier"
assert_equal "$(bundle_value "$WIDGET_BUNDLE" CFBundleIdentifier)" "$WIDGET_BUNDLE_ID" "widget bundle identifier"
assert_equal "$(bundle_value "$APP_BUNDLE" CFBundleShortVersionString)" "$EXPECTED_VERSION" "app marketing version"
assert_equal "$(bundle_value "$APP_BUNDLE" CFBundleVersion)" "$EXPECTED_BUILD" "app build version"
assert_equal "$(bundle_value "$WIDGET_BUNDLE" CFBundleShortVersionString)" "$EXPECTED_VERSION" "widget marketing version"
assert_equal "$(bundle_value "$WIDGET_BUNDLE" CFBundleVersion)" "$EXPECTED_BUILD" "widget build version"
assert_equal "$(signed_architectures "$APP_BUNDLE")" "arm64" "app architecture"
assert_equal "$(signed_architectures "$WIDGET_BUNDLE")" "arm64" "widget architecture"
assert_equal "$(team_identifier "$APP_BUNDLE")" "$TEAM_ID" "app signing team"
assert_equal "$(team_identifier "$WIDGET_BUNDLE")" "$TEAM_ID" "widget signing team"
assert_equal "$(plist_value "$APP_ENTITLEMENTS" 'com\.apple\.application-identifier')" "$TEAM_ID.$APP_BUNDLE_ID" "app application identifier entitlement"
assert_equal "$(plist_value "$APP_ENTITLEMENTS" 'com\.apple\.developer\.team-identifier')" "$TEAM_ID" "app team entitlement"
assert_equal "$(plist_value "$APP_ENTITLEMENTS" 'com\.apple\.security\.app-sandbox')" "true" "app sandbox entitlement"
assert_equal "$(plist_value "$WIDGET_ENTITLEMENTS" 'com\.apple\.security\.app-sandbox')" "true" "widget sandbox entitlement"
assert_equal "$(plist_value "$APP_ENTITLEMENTS" 'com\.apple\.security\.application-groups.0')" "$APP_GROUP" "app App Group entitlement"
assert_equal "$(plist_value "$WIDGET_ENTITLEMENTS" 'com\.apple\.security\.application-groups.0')" "$APP_GROUP" "widget App Group entitlement"

APP_KVS="$(plist_value "$APP_ENTITLEMENTS" 'com\.apple\.developer\.ubiquity-kvstore-identifier')"
assert_equal "$APP_KVS" "$TEAM_ID.io.github.agrim.batterystats" "app iCloud KVS entitlement"

APP_PROFILE="$APP_BUNDLE/Contents/embedded.provisionprofile"
if [[ ! -f "$APP_PROFILE" ]]; then
  fail "the iCloud-enabled app is missing Contents/embedded.provisionprofile"
fi

PROFILE_PLIST="$TMP_DIR/profile.plist"
security cms -D -i "$APP_PROFILE" >"$PROFILE_PLIST"
PROFILE_KVS="$(plist_value "$PROFILE_PLIST" 'Entitlements.com\.apple\.developer\.ubiquity-kvstore-identifier')"
if [[ "$PROFILE_KVS" != "$APP_KVS" && "$PROFILE_KVS" != "$TEAM_ID.*" ]]; then
  fail "the embedded profile does not authorize the effective iCloud KVS entitlement"
fi

if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
  if [[ "$(plist_value "$APP_ENTITLEMENTS" 'com\.apple\.security\.get-task-allow')" == "true"
        || "$(plist_value "$WIDGET_ENTITLEMENTS" 'com\.apple\.security\.get-task-allow')" == "true" ]]; then
    fail "Developer ID products must not contain get-task-allow"
  fi

  for bundle in "$APP_BUNDLE" "$WIDGET_BUNDLE"; do
    release_sign_details="$(codesign -dv --verbose=4 "$bundle" 2>&1)"
    release_authority="$(printf '%s\n' "$release_sign_details" | sed -n 's/^Authority=//p' | head -1)"
    if [[ "$release_authority" != "Developer ID Application:"* ]]; then
      fail "release bundle is not signed by a Developer ID Application identity: $bundle"
    fi
    if [[ "$release_sign_details" != *"Timestamp="* ]]; then
      fail "release bundle is missing a trusted signing timestamp: $bundle"
    fi
  done
fi

for bundle in "$APP_BUNDLE" "$WIDGET_BUNDLE"; do
  code_sign_details="$(codesign -dv --verbose=4 "$bundle" 2>&1)"
  if [[ "$code_sign_details" != *flags=*runtime* ]]; then
    fail "hardened runtime is missing from $bundle"
  fi
done

printf 'verified signed product: %s %s (%s), team %s, shared group %s\n' \
  "$APP_NAME" "$EXPECTED_VERSION" "$EXPECTED_BUILD" "$TEAM_ID" "$APP_GROUP"
