#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:---dry-run}"

usage() {
  echo "usage: $0 [--dry-run|--apply]"
}

case "$MODE" in
  -h|--help|help)
    usage
    exit 0
    ;;
  --dry-run|--apply)
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

TARGETS=(
  "$ROOT_DIR/.build"
  "$ROOT_DIR/build"
  "$ROOT_DIR/DerivedData"
)

for target in "${TARGETS[@]}"; do
  if [[ -e "$target" ]]; then
    if [[ "$MODE" == "--apply" ]]; then
      rm -rf "$target"
      echo "removed ${target#$ROOT_DIR/}"
    else
      du -sh "$target"
    fi
  fi
done
