#!/bin/bash
# Prepare the pinned LGPL libvips build for Apple Silicon (sharp-libvips 1.3.4).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/vendor/libvips"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
URL='https://registry.npmjs.org/@img/sharp-libvips-darwin-arm64/-/sharp-libvips-darwin-arm64-1.3.4.tgz'
EXPECTED='e51f3d9c162245d5254962713e13be195b5a5f35d2c4a9d1bbfc6a327dca4c0dcbf4407d3b2fcff8d9f67f6be584fb94772fd9bac6f60daadbc93a4609f103bb'
mkdir -p "$DEST"
curl -fL --retry 3 -o "$TMP/package.tgz" "$URL"
ACTUAL="$(shasum -a 512 "$TMP/package.tgz" | cut -d' ' -f1)"
[ "$ACTUAL" = "$EXPECTED" ] || { echo 'libvips checksum mismatch' >&2; exit 1; }
tar -xzf "$TMP/package.tgz" -C "$TMP"
cp "$TMP/package/lib/libvips-cpp.8.18.7.dylib" "$DEST/"
cp "$TMP/package/README.md" "$TMP/package/versions.json" "$DEST/"
curl -fL -o "$DEST/LGPL-3.0.txt" https://www.gnu.org/licenses/lgpl-3.0.txt
curl -fL -o "$DEST/GPL-3.0.txt" https://www.gnu.org/licenses/gpl-3.0.txt
cat > "$DEST/SOURCES.txt" <<'EOF'
libvips build: @img/sharp-libvips-darwin-arm64 1.3.4, libvips 8.18.7.
Build scripts: https://github.com/lovell/sharp-libvips/tree/v1.3.4
Package: https://registry.npmjs.org/@img/sharp-libvips-darwin-arm64/-/sharp-libvips-darwin-arm64-1.3.4.tgz
Source: https://github.com/libvips/libvips/tree/v8.18.7
README.md and versions.json describe bundled components and licenses.
EOF
clang -O2 "$ROOT/scripts/native/vips_helper.c" -o "$DEST/vips-helper"
