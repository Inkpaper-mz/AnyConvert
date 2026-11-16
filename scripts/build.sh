#!/bin/bash
# 构建「万能转码」.app
#   ./scripts/build.sh              # 当前架构（Apple 芯片 arm64）
#   ARCHS="arm64 x86_64" ./scripts/build.sh   # 通用二进制（Intel + Apple 芯片）
#   DMG=1 ./scripts/build.sh        # 额外生成 dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="万能转码"
DIST="$ROOT/dist"
BUILD="$ROOT/build"
BUNDLE="$DIST/$APP_NAME.app"
ARCHS="${ARCHS:-$(uname -m)}"
FULL_OFFLINE="${FULL_OFFLINE:-1}"

# 完整离线包不得静默依赖目标机器上的程序。
if [ "$FULL_OFFLINE" = "1" ]; then
    [ "${BUNDLE_LO:-1}" = "1" ] || { echo "错误：完整离线包必须包含 LibreOffice" >&2; exit 1; }
    LO="$ROOT/crossplatform/vendor/LibreOffice.app/Contents/MacOS/soffice"
    [ -x "$LO" ] || { echo "错误：缺少 LibreOffice。请运行 python3 scripts/fetch_engines.py --libreoffice" >&2; exit 1; }
    for arch in $ARCHS; do
        case "$arch" in
            arm64) dir="$ROOT/vendor" ;;
            x86_64) dir="$ROOT/vendor/intel" ;;
            *) echo "错误：不支持的架构 $arch" >&2; exit 1 ;;
        esac
        for name in ffmpeg ffprobe; do
            [ -x "$dir/$name" ] || { echo "错误：缺少 $dir/$name。请运行 scripts/fetch_ffmpeg.sh（Intel 加 WITH_INTEL=1）" >&2; exit 1; }
            lipo -verify_arch "$arch" "$dir/$name" || { echo "错误：$dir/$name 不支持 $arch" >&2; exit 1; }
        done
        [ "$arch" = arm64 ] || { echo "错误：完整离线包的 SVG 引擎目前仅提供 arm64" >&2; exit 1; }
        [ -x "$ROOT/vendor/libvips/vips-helper" ] && [ -f "$ROOT/vendor/libvips/libvips-cpp.8.18.7.dylib" ] && [ -f "$ROOT/vendor/libvips/README.md" ] && [ -f "$ROOT/vendor/libvips/LGPL-3.0.txt" ] && [ -f "$ROOT/vendor/libvips/GPL-3.0.txt" ] || { echo "错误：缺少 SVG 引擎或许可证；请运行 scripts/fetch_libvips.sh" >&2; exit 1; }
        [ -x "$ROOT/vendor/libraw/dcraw_emu" ] && [ -f "$ROOT/vendor/libraw/libraw.25.dylib" ] && [ -f "$ROOT/vendor/libraw/LICENSE.LGPL" ] || { echo "错误：缺少 RAW 引擎或许可证；请运行 scripts/fetch_libraw.sh" >&2; exit 1; }
        if [ "$arch" = arm64 ]; then PANDOC="$ROOT/vendor/pandoc/pandoc"; else PANDOC="$ROOT/vendor/pandoc/intel/pandoc"; fi
        [ -x "$PANDOC" ] && lipo -verify_arch "$arch" "$PANDOC" || { echo "错误：缺少 $arch 的 Pandoc，请先准备对应架构的引擎" >&2; exit 1; }
        [ -f "$ROOT/vendor/pandoc/COPYING.md" ] && [ -f "$ROOT/vendor/pandoc/COPYRIGHT" ] || { echo "错误：缺少 Pandoc 许可证文件" >&2; exit 1; }
        lipo -verify_arch "$arch" "$LO" || { echo "错误：内置 LibreOffice 不支持 $arch；请为每种架构分别打包" >&2; exit 1; }
    done
fi

echo "==> 清理"
rm -rf "$BUILD" "$BUNDLE"
mkdir -p "$DIST" "$BUILD"

echo "==> 编译 Swift（架构: ${ARCHS}）"
if [ "$ARCHS" = "arm64 x86_64" ] || [ "$ARCHS" = "x86_64 arm64" ]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
else
    ARCH_FLAGS=(--arch "$ARCHS")
fi
swift build -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)/AnyConvert"
[ -x "$BIN" ] || { echo "找不到编译产物: $BIN"; exit 1; }
echo "    产物: $BIN"

echo "==> 组装 App Bundle"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/bin"
cp "$BIN" "$BUNDLE/Contents/MacOS/AnyConvert"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "$ROOT/Resources/Strings.json" "$BUNDLE/Contents/Resources/"
for lproj in "$ROOT"/Resources/*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "$BUNDLE/Contents/Resources/"
done
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

echo "==> 生成图标"
swift "$ROOT/scripts/make_icon.swift" "$BUILD/AppIcon.iconset" >/dev/null
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUNDLE/Contents/Resources/AppIcon.icns"

# 内置 LibreOffice（文档 / 表格 / 演示引擎）
if [ "${BUNDLE_LO:-1}" = "1" ] && [ -d "$ROOT/crossplatform/vendor/LibreOffice.app" ]; then
    echo "==> 内置 LibreOffice（约 800 MB）"
    rm -rf "$BUNDLE/Contents/Resources/LibreOffice.app"
    cp -R "$ROOT/crossplatform/vendor/LibreOffice.app" "$BUNDLE/Contents/Resources/LibreOffice.app"
    dot_clean -m "$BUNDLE/Contents/Resources/LibreOffice.app" 2>/dev/null || true
    xattr -cr "$BUNDLE/Contents/Resources/LibreOffice.app" 2>/dev/null || true
fi

echo "==> 内置 FFmpeg 引擎"
for arch in $ARCHS; do
    if [ "$arch" = "arm64" ]; then
        SRC_DIR="$ROOT/vendor"
    else
        SRC_DIR="$ROOT/vendor/intel"
    fi
    if [ -x "$SRC_DIR/ffmpeg" ] && [ -x "$SRC_DIR/ffprobe" ]; then
        cp "$SRC_DIR/ffmpeg" "$BUNDLE/Contents/Resources/bin/ffmpeg-$arch"
        cp "$SRC_DIR/ffprobe" "$BUNDLE/Contents/Resources/bin/ffprobe-$arch"
        chmod +x "$BUNDLE/Contents/Resources/bin/"*
        echo "    ffmpeg-$arch ← $SRC_DIR"
    else
        echo "    警告: 缺少 $SRC_DIR 下的 ffmpeg/ffprobe，应用将回退到系统 ffmpeg"
    fi
done

echo "==> 内置 Pandoc"
for arch in $ARCHS; do
    if [ "$arch" = arm64 ]; then PANDOC="$ROOT/vendor/pandoc/pandoc"; else PANDOC="$ROOT/vendor/pandoc/intel/pandoc"; fi
    if [ -x "$PANDOC" ]; then cp "$PANDOC" "$BUNDLE/Contents/Resources/bin/pandoc-$arch"; fi
done
if [ -f "$ROOT/vendor/pandoc/COPYING.md" ] && [ -f "$ROOT/vendor/pandoc/COPYRIGHT" ]; then
    mkdir -p "$BUNDLE/Contents/Resources/licenses/pandoc"
    cp "$ROOT/vendor/pandoc/COPYING.md" "$ROOT/vendor/pandoc/COPYRIGHT" "$BUNDLE/Contents/Resources/licenses/pandoc/"
fi

echo "==> 内置 SVG 渲染引擎"
if [ -x "$ROOT/vendor/libvips/vips-helper" ]; then
    cp "$ROOT/vendor/libvips/vips-helper" "$BUNDLE/Contents/Resources/bin/vips-helper-arm64"
    cp "$ROOT/vendor/libvips/libvips-cpp.8.18.7.dylib" "$BUNDLE/Contents/Resources/bin/"
    mkdir -p "$BUNDLE/Contents/Resources/licenses/libvips"
    cp "$ROOT/vendor/libvips/README.md" "$ROOT/vendor/libvips/versions.json" "$ROOT/vendor/libvips/SOURCES.txt" "$ROOT/vendor/libvips/LGPL-3.0.txt" "$ROOT/vendor/libvips/GPL-3.0.txt" "$BUNDLE/Contents/Resources/licenses/libvips/"
fi

echo "==> 内置 RAW 引擎"
if [ -x "$ROOT/vendor/libraw/dcraw_emu" ]; then
    cp "$ROOT/vendor/libraw/dcraw_emu" "$BUNDLE/Contents/Resources/bin/dcraw_emu-arm64"
    cp "$ROOT/vendor/libraw/libraw.25.dylib" "$BUNDLE/Contents/Resources/bin/"
    mkdir -p "$BUNDLE/Contents/Resources/licenses/libraw"
    cp "$ROOT/vendor/libraw/LICENSE.LGPL" "$ROOT/vendor/libraw/recipe.yaml" "$BUNDLE/Contents/Resources/licenses/libraw/"
fi

echo "==> 签名（ad-hoc）"
dot_clean -m "$BUNDLE" 2>/dev/null || true
xattr -cr "$BUNDLE" 2>/dev/null || true
codesign --force --sign - "$BUNDLE/Contents/MacOS/AnyConvert"
for bin in "$BUNDLE/Contents/Resources/bin/"*; do
    [ -f "$bin" ] && codesign --force --sign - "$bin"
done
codesign --force --sign - "$BUNDLE" || {
    echo "错误：应用签名失败；请在本地非文件同步目录构建后重试" >&2
    exit 1
}
codesign --verify --deep --strict "$BUNDLE" || {
    echo "错误：应用签名校验失败，已停止打包" >&2
    exit 1
}
echo "    签名校验通过（ad-hoc，未公证）"

SIZE=$(du -sh "$BUNDLE" | cut -f1)
echo "==> 完成: $BUNDLE ($SIZE)"

if [ "${DMG:-0}" = "1" ]; then
    echo "==> 制作 DMG"
    STAGE="$BUILD/dmg"
    rm -rf "$STAGE"; mkdir -p "$STAGE"
    cp -R "$BUNDLE" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    rm -f "$DIST/$APP_NAME.dmg"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DIST/$APP_NAME.dmg"
    echo "==> DMG: $DIST/$APP_NAME.dmg ($(du -sh "$DIST/$APP_NAME.dmg" | cut -f1))"
fi
