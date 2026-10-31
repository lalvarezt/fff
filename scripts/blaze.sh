#!/usr/bin/env bash
set -euo pipefail

blaze_bin=${BLAZE:-blaze}
if ! command -v "$blaze_bin" >/dev/null 2>&1; then
  echo 'Blaze is required. See README.md#iterate-with-blaze for installation.' >&2
  exit 1
fi

case "${1:-}" in
  build|test|check|run)
    zvm_bin=$(command -v zvm || true)
    if [[ -z "$zvm_bin" && -x "$HOME/.zvm/self/zvm" ]]; then
      zvm_bin="$HOME/.zvm/self/zvm"
    fi
    if [[ -n "$zvm_bin" ]]; then
      original_path=$PATH
      zvm_env=$("$zvm_bin" env 0.16.0)
      eval "$zvm_env"
      # A new zvm multishell path on every build invalidates Blaze's workers.
      zig_dir=$(cd -P -- "$(dirname -- "$(command -v zig)")" && pwd)
      export PATH="$zig_dir:$original_path"
      unset ZVM_MULTISHELL_PATH
    fi
    ;;
esac

export BLAZE_BACKEND=${BLAZE_BACKEND:-cranelift}
exec "$blaze_bin" "$@"
