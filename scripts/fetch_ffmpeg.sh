#!/bin/bash
# 下载静态 FFmpeg / ffprobe 到 vendor/ 目录
#   ./scripts/fetch_ffmpeg.sh              # Apple 芯片（arm64）
#   WITH_INTEL=1 ./scripts/fetch_ffmpeg.sh # 同时下载 Intel（amd64）
#   PROXY=http://127.0.0.1:7890 ./scripts/fetch_ffmpeg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BASE="https://ffmpeg.martin-riedl.de/redirect/latest/macos"
CURL=(curl -fL --retry 3 --connect-timeout 20)
if [ -n "${PROXY:-}" ]; then
    CURL+=(-x "$PROXY")
fi

fetch_arch() {
    local arch="$1" dir="$2"
    mkdir -p "$dir"
    for bin in ffmpeg ffprobe; do
        if [ -x "$dir/$bin" ]; then
            echo "已存在：$dir/$bin"
            continue
        fi
        echo "下载 $bin ($arch)…"
        "${CURL[@]}" -o "/tmp/$bin-$arch.zip" "$BASE/$arch/release/$bin.zip"
        unzip -o -q "/tmp/$bin-$arch.zip" -d "$dir"
        chmod +x "$dir/$bin"
        rm -f "/tmp/$bin-$arch.zip"
    done
}

fetch_arch arm64 vendor
if [ "${WITH_INTEL:-0}" = "1" ]; then
    fetch_arch amd64 vendor/intel
fi

echo "完成："
for f in vendor/ffmpeg vendor/ffprobe vendor/intel/ffmpeg vendor/intel/ffprobe; do
    [ -x "$f" ] && echo "  $f"
done
