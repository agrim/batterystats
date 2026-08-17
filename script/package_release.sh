#!/usr/bin/env bash
set -euo pipefail

APP_NAME="BatteryStats"
TEAM_ID="${BATTERYSTATS_TEAM_ID:-Q293G85PG5}"
SIGNING_IDENTITY="${BATTERYSTATS_DEVELOPER_IDENTITY:-Developer ID Application: Agrim Gupta (Q293G85PG5)}"
NOTARY_PROFILE="${BATTERYSTATS_NOTARY_PROFILE:-BatteryStats}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/BatteryStats.xcodeproj"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/.build/Release/BatteryStats.xcarchive}"
EXPORT_DIR="${EXPORT_DIR:-$ROOT_DIR/.build/Release/Export}"
STAGING_DIR="${STAGING_DIR:-$ROOT_DIR/.build/Release/DMG}"
OUTPUT_DMG="${OUTPUT_DMG:-$ROOT_DIR/dist/BatteryStats-arm64-1.0.4.dmg}"
EXPORT_OPTIONS="$ROOT_DIR/script/DeveloperIDExportOptions.plist"

require_safe_build_path() {
  local path="$1"
  local label="$2"
  case "$path" in
    "$ROOT_DIR/.build/"?*)
      ;;
    *)
      printf 'error: %s must stay below %s/.build\n' "$label" "$ROOT_DIR" >&2
      exit 2
      ;;
  esac
  if [[ "$path" == *"/../"* || "$path" == */.. ]]; then
    printf 'error: %s must not contain parent-directory traversal\n' "$label" >&2
    exit 2
  fi
}

require_safe_build_path "$ARCHIVE_PATH" ARCHIVE_PATH
require_safe_build_path "$EXPORT_DIR" EXPORT_DIR
require_safe_build_path "$STAGING_DIR" STAGING_DIR
if [[ "$ARCHIVE_PATH" != *.xcarchive ]]; then
  printf 'error: ARCHIVE_PATH must end in .xcarchive\n' >&2
  exit 2
fi
case "$OUTPUT_DMG" in
  "$ROOT_DIR/dist/BatteryStats-arm64-"?*.dmg)
    ;;
  *)
    printf 'error: OUTPUT_DMG must be a versioned BatteryStats DMG below %s/dist\n' "$ROOT_DIR" >&2
    exit 2
    ;;
esac
if [[ "$OUTPUT_DMG" == *"/../"* || "$OUTPUT_DMG" == */.. ]]; then
  printf 'error: OUTPUT_DMG must not contain parent-directory traversal\n' >&2
  exit 2
fi

if [[ "${BATTERYSTATS_ALLOW_PROVISIONING_UPDATES:-0}" != "1" ]]; then
  printf 'error: release export requires BATTERYSTATS_ALLOW_PROVISIONING_UPDATES=1 so Xcode can refresh the Developer ID iCloud profile\n' >&2
  exit 2
fi

cd "$ROOT_DIR"
xcodegen generate

rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$STAGING_DIR"
mkdir -p "$EXPORT_DIR" "$STAGING_DIR"

xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  "DEVELOPMENT_TEAM=$TEAM_ID" \
  ARCHS=arm64 \
  CODE_SIGN_STYLE=Automatic

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

EXPORTED_APP="$EXPORT_DIR/$APP_NAME.app"
BATTERYSTATS_REQUIRE_DEVELOPER_ID=1 "$ROOT_DIR/script/verify_signed_product.sh" "$EXPORTED_APP"

/usr/bin/ditto "$EXPORTED_APP" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$OUTPUT_DMG" "$OUTPUT_DMG.sha256"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG"

codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$OUTPUT_DMG"
xcrun notarytool submit "$OUTPUT_DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$OUTPUT_DMG"
xcrun stapler validate "$OUTPUT_DMG"
spctl -a -t open --context context:primary-signature -vv "$OUTPUT_DMG"
(
  cd "$(dirname "$OUTPUT_DMG")"
  output_name="$(basename "$OUTPUT_DMG")"
  shasum -a 256 "$output_name" >"$output_name.sha256"
)

printf 'created signed, notarized, stapled release candidate: %s\n' "$OUTPUT_DMG"
