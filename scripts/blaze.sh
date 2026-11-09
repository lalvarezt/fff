#!/usr/bin/env bash
set -euo pipefail

blaze_bin=${BLAZE:-blaze}
if ! command -v "$blaze_bin" >/dev/null 2>&1; then
  echo 'Blaze is required. See README.md#iterate-with-blaze for installation.' >&2
  exit 1
fi

export BLAZE_BACKEND=${BLAZE_BACKEND:-cranelift}
case "${1:-}" in
  build|test|check|run)
    exec bash "$(dirname "$0")/with-zig.sh" "$blaze_bin" "$@"
    ;;
esac

exec "$blaze_bin" "$@"
