#!/bin/bash
# Prepare the pinned Apple Silicon Pandoc binary and its license notices.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/vendor/pandoc"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
python3 -m pip download --no-deps --only-binary=:all: --platform macosx_11_0_arm64 --python-version 311 --dest "$TMP" 'pypandoc_binary==1.17'
WHEEL="$TMP/pypandoc_binary-1.17-py3-none-macosx_11_0_arm64.whl"
EXPECTED=fcfd28f347ed998dda28823fc6bc24f9310e7fdf3ddceaf925bf0563a100ab5b
[ "$(shasum -a 256 "$WHEEL" | cut -d' ' -f1)" = "$EXPECTED" ] || { echo 'Pandoc checksum mismatch' >&2; exit 1; }
mkdir -p "$DEST"
unzip -p "$WHEEL" pypandoc/files/pandoc > "$DEST/pandoc"
chmod +x "$DEST/pandoc"
curl -fL -o "$DEST/COPYING.md" https://raw.githubusercontent.com/jgm/pandoc/3.9/COPYING.md
curl -fL -o "$DEST/COPYRIGHT" https://raw.githubusercontent.com/jgm/pandoc/3.9/COPYRIGHT
"$DEST/pandoc" --version | head -1
