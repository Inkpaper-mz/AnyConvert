#!/bin/bash
# Prepare LibRaw 0.22.2 for Apple Silicon. Requires Python 3 and pip at build time.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/vendor/libraw"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
URL='https://conda.anaconda.org/conda-forge/osx-arm64/libraw-0.22.2-h2d05ff4_0.conda'
EXPECTED='e3e654527f10346ca39fe628bb6f81dadf946647e5c081f84703ab654ae15a45'
[ -f "$ROOT/vendor/libvips/libvips-cpp.8.18.7.dylib" ] || { echo '请先运行 scripts/fetch_libvips.sh' >&2; exit 1; }
curl -fL --retry 3 -o "$TMP/libraw.conda" "$URL"
[ "$(shasum -a 256 "$TMP/libraw.conda" | cut -d' ' -f1)" = "$EXPECTED" ] || { echo 'LibRaw checksum mismatch' >&2; exit 1; }
python3 -m pip install --quiet --target "$TMP/py" zstandard
unzip -oq "$TMP/libraw.conda" -d "$TMP"
PYTHONPATH="$TMP/py" python3 - "$TMP" <<'PY'
import glob, io, os, sys, tarfile, zstandard
root = sys.argv[1]
for filename in glob.glob(os.path.join(root, '*.tar.zst')):
    with open(filename, 'rb') as f:
        data = zstandard.ZstdDecompressor().stream_reader(f).read()
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for name in ('bin/dcraw_emu', 'lib/libraw.25.dylib', 'info/licenses/libraw/LICENSE.LGPL', 'info/recipe/recipe.yaml'):
            try: member = archive.getmember(name)
            except KeyError: continue
            if not member.isfile(): raise RuntimeError('Unexpected LibRaw archive member')
            dest = os.path.join(root, os.path.basename(name))
            with archive.extractfile(member) as src, open(dest, 'wb') as out: out.write(src.read())
PY
mkdir -p "$DEST"
cp "$TMP/dcraw_emu" "$TMP/libraw.25.dylib" "$TMP/LICENSE.LGPL" "$TMP/recipe.yaml" "$DEST/"
chmod +x "$DEST/dcraw_emu" "$DEST/libraw.25.dylib"
ln -sf ../libvips/libvips-cpp.8.18.7.dylib "$DEST/libvips-cpp.8.18.7.dylib"
install_name_tool -change @rpath/libraw.25.dylib @loader_path/libraw.25.dylib -change @rpath/libc++.1.dylib /usr/lib/libc++.1.dylib "$DEST/dcraw_emu"
install_name_tool -change @rpath/libjpeg.8.dylib @loader_path/libvips-cpp.8.18.7.dylib -change @rpath/liblcms2.2.dylib @loader_path/libvips-cpp.8.18.7.dylib -change @rpath/libz.1.dylib /usr/lib/libz.1.dylib -change @rpath/libc++.1.dylib /usr/lib/libc++.1.dylib "$DEST/libraw.25.dylib"
codesign --force --sign - "$DEST/libraw.25.dylib"
codesign --force --sign - "$DEST/dcraw_emu"
