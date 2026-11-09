#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${ZIG:-}" ]]; then
  zvm_bin=$(command -v zvm || true)
  if [[ -z "$zvm_bin" && -x "$HOME/.zvm/self/zvm" ]]; then
    zvm_bin="$HOME/.zvm/self/zvm"
  fi
  if [[ -n "$zvm_bin" ]]; then
    original_path=$PATH
    zvm_env=$("$zvm_bin" env --shell bash)
    eval "$zvm_env"
    "$zvm_bin" use 0.16.0
    # Keep the compiler path stable across zvm multishells for Blaze workers.
    zig_dir=$(cd -P -- "$(dirname -- "$(command -v zig)")" && pwd)
    export PATH="$zig_dir:$original_path"
    unset ZVM_MULTISHELL_PATH
  fi
fi

exec "$@"
