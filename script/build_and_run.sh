#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
if (($# > 0)); then
  shift
fi

EXTRA_XCODEBUILD_ARGS=("$@")
APP_NAME="BatteryStats"
BUNDLE_ID="io.github.agrim.batterystats"
TEAM_ID="${BATTERYSTATS_TEAM_ID:-Q293G85PG5}"
DESTINATION="${DESTINATION:-platform=macOS,arch=arm64}"
CONFIGURATION="${CONFIGURATION:-Debug}"
SIGNING_MODE="${BATTERYSTATS_SIGNING_MODE:-automatic}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/BatteryStats.xcodeproj"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/DerivedData}"
TEST_DERIVED_DATA_PATH="${TEST_DERIVED_DATA_PATH:-$ROOT_DIR/.build/DerivedDataTests}"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
TEST_APP_BUNDLE="$TEST_DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
TEST_WIDGET_BUNDLE="$TEST_APP_BUNDLE/Contents/PlugIns/BatteryStatsWidgetsExtension.appex"
PRODUCT_VERIFIER="$ROOT_DIR/script/verify_signed_product.sh"
INSTALL_VERIFIER="$ROOT_DIR/script/verify_installed_widget.sh"

SIGNING_ARGS=()
PROVISIONING_ARGS=()

normalize_xcodebuild_args() {
  if ((${#EXTRA_XCODEBUILD_ARGS[@]} == 0)); then
    return
  fi

  local normalized=()
  local arg
  for arg in "${EXTRA_XCODEBUILD_ARGS[@]}"; do
    case "$arg" in
      --only-testing|--skip-testing|--only-testing:*|--skip-testing:*)
        normalized+=("-${arg#--}")
        ;;
      *)
        normalized+=("$arg")
        ;;
    esac
  done

  EXTRA_XCODEBUILD_ARGS=("${normalized[@]}")
}

configure_signing() {
  case "$SIGNING_MODE" in
    automatic)
      SIGNING_ARGS=(
        "DEVELOPMENT_TEAM=$TEAM_ID"
        "CODE_SIGN_STYLE=Automatic"
      )
      if [[ "${BATTERYSTATS_ALLOW_PROVISIONING_UPDATES:-0}" == "1" ]]; then
        PROVISIONING_ARGS+=("-allowProvisioningUpdates")
        PROVISIONING_ARGS+=("-allowProvisioningDeviceRegistration")
      fi
      ;;
    unsigned)
      SIGNING_ARGS=("CODE_SIGNING_ALLOWED=NO")
      ;;
    *)
      printf 'error: BATTERYSTATS_SIGNING_MODE must be automatic or unsigned, got %s\n' "$SIGNING_MODE" >&2
      exit 2
      ;;
  esac
}

usage() {
  cat <<'EOF'
usage: ./script/build_and_run.sh [run|build|install|test|--test|--debug|--logs|--telemetry|--verify] [xcodebuild arguments]

The default run/build/install path is signed so WidgetKit, App Groups, iCloud KVS,
and launch-at-login are tested under their real security model. On the first build,
set BATTERYSTATS_ALLOW_PROVISIONING_UPDATES=1 if Xcode needs to create or refresh
the iCloud provisioning profile.

Unsigned builds are only an explicit compile/test fallback:
  BATTERYSTATS_SIGNING_MODE=unsigned ./script/build_and_run.sh build
EOF
}

build_app() {
  if [[ -d "$APP_BUNDLE/Contents/PlugIns/BatteryStatsTests.xctest" ]]; then
    printf 'removing runtime product contaminated by a stale test bundle: %s\n' "$APP_BUNDLE"
    rm -rf "$APP_BUNDLE"
  fi

  local args=(
    -project "$PROJECT_PATH"
    -scheme "$APP_NAME"
    -configuration "$CONFIGURATION"
    -destination "$DESTINATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
  )
  if ((${#EXTRA_XCODEBUILD_ARGS[@]} > 0)); then
    args+=("${EXTRA_XCODEBUILD_ARGS[@]}")
  fi

  if ((${#PROVISIONING_ARGS[@]} > 0)); then
    args+=("${PROVISIONING_ARGS[@]}")
  fi
  args+=("${SIGNING_ARGS[@]}")

  xcodebuild "${args[@]}" build

  if [[ "$SIGNING_MODE" == "automatic" ]]; then
    "$PRODUCT_VERIFIER" "$APP_BUNDLE"
  fi
}

test_app() {
  local args=(
    test
    -project "$PROJECT_PATH"
    -scheme "$APP_NAME"
    -configuration "$CONFIGURATION"
    -destination "$DESTINATION"
    -derivedDataPath "$TEST_DERIVED_DATA_PATH"
  )
  if ((${#EXTRA_XCODEBUILD_ARGS[@]} > 0)); then
    args+=("${EXTRA_XCODEBUILD_ARGS[@]}")
  fi

  if ((${#PROVISIONING_ARGS[@]} > 0)); then
    args+=("${PROVISIONING_ARGS[@]}")
  fi
  args+=("${SIGNING_ARGS[@]}")

  local status
  if xcodebuild "${args[@]}"; then
    status=0
  else
    status=$?
  fi

  if [[ -d "$TEST_WIDGET_BUNDLE" ]]; then
    pluginkit -r "$TEST_WIDGET_BUNDLE" >/dev/null 2>&1 || true
  fi

  return "$status"
}

require_signed_runtime() {
  if [[ "$SIGNING_MODE" == "unsigned" ]]; then
    printf 'error: %s requires a signed build; use unsigned mode only for compile/test checks\n' "$MODE" >&2
    exit 2
  fi
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

install_app() {
  local installed_app="${BATTERYSTATS_INSTALL_PATH:-/Applications/$APP_NAME.app}"
  local built_widget="$APP_BUNDLE/Contents/PlugIns/BatteryStatsWidgetsExtension.appex"
  local old_widget="$installed_app/Contents/PlugIns/BatteryStatsWidgetsExtension.appex"
  local new_widget

  case "$installed_app" in
    /*/BatteryStats.app)
      ;;
    *)
      printf 'error: BATTERYSTATS_INSTALL_PATH must be an absolute path ending in /BatteryStats.app\n' >&2
      exit 2
      ;;
  esac
  if [[ "$installed_app" == *"/../"* ]]; then
    printf 'error: BATTERYSTATS_INSTALL_PATH must not contain parent-directory traversal\n' >&2
    exit 2
  fi

  if [[ -d "$old_widget" ]]; then
    pluginkit -r "$old_widget" >/dev/null 2>&1 || true
  fi

  rm -rf "$installed_app"
  /usr/bin/ditto "$APP_BUNDLE" "$installed_app"
  new_widget="$installed_app/Contents/PlugIns/BatteryStatsWidgetsExtension.appex"
  pluginkit -r "$built_widget" >/dev/null 2>&1 || true
  while IFS= read -r registered_widget; do
    if [[ -n "$registered_widget" && "$registered_widget" != "$new_widget" ]]; then
      pluginkit -r "$registered_widget" >/dev/null 2>&1 || true
    fi
  done < <(
    pluginkit -m -A -D -v -i "io.github.agrim.batterystats.widgets" 2>&1 \
      | awk -F '\t' '/BatteryStatsWidgetsExtension\.appex$/ { print $NF }'
  )
  pluginkit -a "$new_widget"
  local snapshot_not_before
  snapshot_not_before="$(($(date +%s) - 978307200))"
  /usr/bin/open -n "$installed_app"
  sleep 2
  BATTERYSTATS_REQUIRE_SHARED_SNAPSHOT=1 \
    BATTERYSTATS_EXPECT_SNAPSHOT_AFTER="$snapshot_not_before" \
    "$INSTALL_VERIFIER" "$installed_app"
}

verify_app_process() {
  local pgrep_error
  pgrep_error="$(mktemp "${TMPDIR:-/tmp}/batterystats-pgrep.XXXXXX")"

  if pgrep -x "$APP_NAME" >/dev/null 2>"$pgrep_error"; then
    rm -f "$pgrep_error"
    return 0
  else
    local status=$?
  fi

  local error_text
  error_text="$(<"$pgrep_error")"
  rm -f "$pgrep_error"

  case "$error_text" in
    *"Cannot get process list"*|*"sysmond service not found"*|*"operation not permitted"*)
      printf 'warning: launched %s, but this environment could not inspect processes: %s\n' "$APP_NAME" "$error_text" >&2
      return 0
      ;;
  esac

  return "$status"
}

normalize_xcodebuild_args
configure_signing

case "$MODE" in
  -h|--help|help)
    usage
    exit 0
    ;;
  test|--test)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    test_app
    exit 0
    ;;
  build)
    build_app
    exit 0
    ;;
esac

case "$MODE" in
  run|install|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

require_signed_runtime
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
build_app

case "$MODE" in
  run)
    open_app
    ;;
  install)
    install_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    "$PRODUCT_VERIFIER" "$APP_BUNDLE"
    verify_app_process
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
