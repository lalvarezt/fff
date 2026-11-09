#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/pinned"

cat > "$fixture/bin/zig" <<'EOF'
#!/usr/bin/env bash
echo 0.17.1
EOF
cat > "$fixture/pinned/zig" <<'EOF'
#!/usr/bin/env bash
echo 0.16.0
EOF
cat > "$fixture/bin/zvm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'env --shell bash')
    printf 'export PATH=%q:$PATH\n' "$(dirname "$0")/../pinned"
    ;;
  'env'*) echo 'set -gx ZVM_MULTISHELL_PATH /tmp/fish-shell' ;;
  'use 0.16.0') ;;
  *) exit 1 ;;
esac
EOF
cat > "$fixture/bin/cargo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
version=$("${ZIG:-zig}" version)
if [[ "$version" != 0.16.0 ]]; then
  echo "Expected Zig 0.16.0, got $version" >&2
  exit 1
fi
EOF
cp "$fixture/bin/cargo" "$fixture/bin/cargo-cbuild"
cp "$fixture/bin/cargo" "$fixture/bin/blaze"
chmod +x "$fixture/bin/"* "$fixture/pinned/zig"

for target in build build-e2e build-c-lib build-mcp; do
  env -u ZIG PATH="$fixture/bin:$PATH" make --no-print-directory "$target"
done
ZIG="$fixture/pinned/zig" PATH="$fixture/bin:$PATH" make --no-print-directory build
env -u ZIG PATH="$fixture/bin:$PATH" bash scripts/blaze.sh build --release
echo 'Build targets select Zig 0.16.0'
