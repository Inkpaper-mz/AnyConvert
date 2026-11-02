#!/usr/bin/env bash
# 打包 macOS .app：把 Qt 界面 + FFmpeg + LibreOffice + PyMuPDF 一起装进去
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d "crossplatform/vendor" ]; then
  echo "先准备引擎：python3 scripts/fetch_engines.py --all"
  exit 1
fi

python3 -m pip install --user --quiet pyinstaller
python3 -m PyInstaller --noconfirm --clean --windowed \
  --name "万能转码" \
  --add-data "crossplatform/core:crossplatform/core" \
  --add-data "crossplatform/vendor:crossplatform/vendor" \
  run_qt.py

echo "完成：dist/万能转码.app"
