#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:-/Applications/BatteryStats.app}"
WIDGET_BUNDLE_ID="io.github.agrim.batterystats.widgets"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WIDGET_BUNDLE="$APP_BUNDLE/Contents/PlugIns/BatteryStatsWidgetsExtension.appex"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/BatteryStats"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

"$ROOT_DIR/script/verify_signed_product.sh" "$APP_BUNDLE"

if [[ ! -d "$WIDGET_BUNDLE" ]]; then
  fail "installed widget bundle is missing"
fi

pluginkit -a "$WIDGET_BUNDLE"

PLUGIN_OUTPUT=""
for _ in 1 2 3 4 5; do
  PLUGIN_OUTPUT="$(pluginkit -m -A -D -v -i "$WIDGET_BUNDLE_ID" 2>&1 || true)"
  if [[ "$PLUGIN_OUTPUT" == *"$WIDGET_BUNDLE"* ]]; then
    break
  fi
  sleep 1
done

if [[ "$PLUGIN_OUTPUT" != *"$WIDGET_BUNDLE"* ]]; then
  printf '%s\n' "$PLUGIN_OUTPUT" >&2
  fail "PluginKit does not resolve the active widget to $WIDGET_BUNDLE"
fi

PLUGIN_PATHS="$(printf '%s\n' "$PLUGIN_OUTPUT" | awk -F '\t' '/BatteryStatsWidgetsExtension\.appex$/ { print $NF }')"
PLUGIN_PATH_COUNT="$(printf '%s\n' "$PLUGIN_PATHS" | awk 'NF { count += 1 } END { print count + 0 }')"
if [[ "$PLUGIN_PATH_COUNT" != "1" || "$PLUGIN_PATHS" != "$WIDGET_BUNDLE" ]]; then
  printf '%s\n' "$PLUGIN_OUTPUT" >&2
  fail "PluginKit has duplicate or stale BatteryStats widget registrations"
fi

if [[ "${BATTERYSTATS_REQUIRE_SHARED_SNAPSHOT:-0}" == "1" ]]; then
  SNAPSHOT_FOUND=0
  REFERENCE_DATE_UNIX_OFFSET=978307200
  EXPECTED_SNAPSHOT_AFTER="${BATTERYSTATS_EXPECT_SNAPSHOT_AFTER:-$(($(date +%s) - REFERENCE_DATE_UNIX_OFFSET - 120))}"
  SNAPSHOT_OUTPUT=""
  for _ in {1..20}; do
    if SNAPSHOT_OUTPUT="$(
      BATTERYSTATS_EXPECT_SNAPSHOT_AFTER="$EXPECTED_SNAPSHOT_AFTER" \
        "$APP_BINARY" --verify-shared-widget-snapshot 2>&1
    )"; then
      SNAPSHOT_FOUND=1
      break
    fi
    sleep 1
  done
  if [[ "$SNAPSHOT_FOUND" != "1" ]]; then
    printf '%s\n' "$SNAPSHOT_OUTPUT" >&2
    fail "the installed app did not publish a new decodable snapshot in the shared App Group"
  fi
  printf '%s\n' "$SNAPSHOT_OUTPUT"
fi

printf 'verified installed widget registration: %s\n' "$WIDGET_BUNDLE"
