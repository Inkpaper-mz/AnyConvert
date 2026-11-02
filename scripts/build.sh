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
ARCHS="${ARCHS:-arm64}"

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

echo "==> 签名（ad-hoc）"
dot_clean -m "$BUNDLE" 2>/dev/null || true
xattr -cr "$BUNDLE" 2>/dev/null || true
codesign --force --sign - "$BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true
for bin in "$BUNDLE/Contents/Resources/bin/"*; do
    [ -f "$bin" ] && codesign --force --sign - "$bin" 2>/dev/null || true
done
codesign --force --sign - "$BUNDLE" 2>/dev/null || echo "    警告：顶层签名失败，继续打包"
if codesign --verify --deep --strict "$BUNDLE" 2>/dev/null; then
    echo "    签名校验通过"
else
    echo "    提示：本地 ad-hoc 签名（首次运行若被拦截请右键 → 打开）"
fi

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
