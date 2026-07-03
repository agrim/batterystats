#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
if (($# > 0)); then
  shift
fi
EXTRA_XCODEBUILD_ARGS=("$@")
APP_NAME="BatteryStats"
BUNDLE_ID="io.github.agrim.batterystats"
DESTINATION="${DESTINATION:-platform=macOS,arch=arm64}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/BatteryStats.xcodeproj"
DERIVED_DATA_PATH="$ROOT_DIR/.build/DerivedData"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

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

usage() {
  echo "usage: $0 [run|test|--test|--debug|--logs|--telemetry|--verify]"
}

normalize_xcodebuild_args

build_app() {
  local args=(
    -project "$PROJECT_PATH"
    -scheme "$APP_NAME"
    -configuration Debug
    -destination "$DESTINATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
  )
  if ((${#EXTRA_XCODEBUILD_ARGS[@]} > 0)); then
    args+=("${EXTRA_XCODEBUILD_ARGS[@]}")
  fi
  args+=(
    CODE_SIGNING_ALLOWED=NO
    build
  )

  xcodebuild "${args[@]}"
}

test_app() {
  local args=(
    test
    -project "$PROJECT_PATH"
    -scheme "$APP_NAME"
    -configuration Debug
    -destination "$DESTINATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
  )
  if ((${#EXTRA_XCODEBUILD_ARGS[@]} > 0)); then
    args+=("${EXTRA_XCODEBUILD_ARGS[@]}")
  fi
  args+=(
    CODE_SIGNING_ALLOWED=NO
  )

  xcodebuild "${args[@]}"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_app() {
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
esac

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

build_app

case "$MODE" in
  run)
    open_app
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
    verify_app
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
