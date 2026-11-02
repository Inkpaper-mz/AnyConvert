#!/usr/bin/env python3
"""打包 Windows / Linux / macOS 的跨平台免安装 zip。"""

from __future__ import annotations

import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERSION = "1.5.1"
OUT = os.path.join(ROOT, "dist", f"AnyConvert-{VERSION}-crossplatform.zip")
PREFIX = f"AnyConvert-{VERSION}"

FILES = [
    "README.md", "START-HERE.txt", "run_web.py",
    "启动-Windows.bat", "启动-Linux.sh", "启动-macOS.command",
    "crossplatform/__init__.py", "crossplatform/cli.py",
    "crossplatform/requirements.txt", "crossplatform/README.md",
    "crossplatform/core/__init__.py", "crossplatform/core/matrix.json",
    "crossplatform/core/matrix.py", "crossplatform/core/queue.py",
    "crossplatform/core/engines.py", "crossplatform/core/compress.py",
    "crossplatform/core/pdf_tools.py", "crossplatform/core/ocr.py",
    "webui/__init__.py", "webui/server.py",
    "webui/static/index.html", "webui/static/app.css", "webui/static/app.js",
    "scripts/fetch_engines.py", "scripts/install_context_menu.py",
    "scripts/run_web.sh", "scripts/fetch_ffmpeg.sh",
    "docs/webui.png",
]


def main() -> int:
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    missing = [name for name in FILES if not os.path.exists(os.path.join(ROOT, name))]
    if missing:
        print("缺少文件：", missing)
        return 1
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in FILES:
            archive.write(os.path.join(ROOT, name), f"{PREFIX}/{name}")
    size = os.path.getsize(OUT) / 1024 / 1024
    print(f"完成：{OUT}（{size:.1f} MB）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
