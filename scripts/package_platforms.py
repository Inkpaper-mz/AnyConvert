#!/usr/bin/env python3
"""生成 1.5.0 三平台包：Windows zip / Linux tar.gz / macOS Web .app zip。"""

from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
import tarfile
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERSION = "1.5.0"
DIST = os.path.join(ROOT, "dist")
PREFIX = f"AnyConvert-{VERSION}"

COMMON = [
    "README.md", "run_web.py",
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

WIN_README = """万能转码 1.5.0 · Windows 版
==============================
1. 安装 Python 3.10+（勾选 Add Python to PATH）
2. 双击 安装依赖.bat（安装依赖 + 下载 FFmpeg / LibreOffice）
3. 双击 启动-Windows.bat，浏览器打开本地界面

命令行：python -m crossplatform.cli --help
右键菜单：python scripts\\install_context_menu.py install
"""

LINUX_README = """万能转码 1.5.0 · Linux 版
============================
1. 安装 Python 3.10+
2. bash install.sh      # 依赖 + LibreOffice；FFmpeg 可用 apt install ffmpeg
3. bash 启动-Linux.sh   # 浏览器打开本地界面

命令行：python3 -m crossplatform.cli --help
右键菜单：python3 scripts/install_context_menu.py install
"""

MAC_README = """万能转码 1.5.0 · macOS（Web UI）
==================================
1. 双击 万能转码.app 启动；首次如提示缺少依赖：
   双击包内的 安装依赖.command（安装 PyMuPDF 等并下载 LibreOffice）
2. 浏览器会自动打开本地界面（仅监听 127.0.0.1）
3. 首次被系统拦截时：右键 万能转码.app → 打开

命令行：python3 -m crossplatform.cli --help
"""

WIN_EXTRAS = {
    "启动-Windows.bat": '@echo off\ncd /d "%~dp0"\npython -m webui.server\npause\n',
    "安装依赖.bat": '@echo off\ncd /d "%~dp0"\npython -m pip install -r crossplatform\\requirements.txt\npython scripts\\fetch_engines.py --all\npause\n',
    "README-Windows.txt": WIN_README,
}
LINUX_EXTRAS = {
    "启动-Linux.sh": '#!/usr/bin/env bash\ncd "$(dirname "$0")"\nexec python3 -m webui.server\n',
    "install.sh": '#!/usr/bin/env bash\nset -e\ncd "$(dirname "$0")"\npython3 -m pip install --user -r crossplatform/requirements.txt\npython3 scripts/fetch_engines.py --all || true\n',
    "README-Linux.txt": LINUX_README,
}


def add_zip(archive: zipfile.ZipFile, prefix: str, extras: dict[str, str]) -> None:
    for name in COMMON:
        archive.write(os.path.join(ROOT, name), f"{prefix}/{name}")
    for name, content in extras.items():
        archive.writestr(f"{prefix}/{name}", content)
        if name.endswith((".sh", ".command")):
            pass


def add_tar(archive: tarfile.TarFile, prefix: str, extras: dict[str, str]) -> None:
    for name in COMMON:
        archive.add(os.path.join(ROOT, name), f"{prefix}/{name}")
    for name, content in extras.items():
        data = content.encode("utf-8")
        info = tarfile.TarInfo(f"{prefix}/{name}")
        info.size = len(data)
        info.mode = 0o755 if name.endswith((".sh", ".command")) else 0o644
        import io
        archive.addfile(info, io.BytesIO(data))


def build_windows() -> None:
    out = os.path.join(DIST, f"AnyConvert-{VERSION}-Windows-x64.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        add_zip(archive, PREFIX, WIN_EXTRAS)
    print(f"{os.path.basename(out)}  {os.path.getsize(out)/1024/1024:.1f} MB")


def build_linux() -> None:
    out = os.path.join(DIST, f"AnyConvert-{VERSION}-Linux-x64.tar.gz")
    with tarfile.open(out, "w:gz") as archive:
        add_tar(archive, PREFIX, LINUX_EXTRAS)
    print(f"{os.path.basename(out)}  {os.path.getsize(out)/1024/1024:.1f} MB")


def build_macos_app() -> None:
    work = tempfile.mkdtemp(prefix="anyconvert-app-")
    bundle = os.path.join(work, "万能转码.app")
    contents = os.path.join(bundle, "Contents")
    resources = os.path.join(contents, "Resources")
    app_dir = os.path.join(resources, "app")
    os.makedirs(os.path.join(contents, "MacOS"), exist_ok=True)
    os.makedirs(app_dir, exist_ok=True)

    for name in COMMON:
        target = os.path.join(app_dir, name)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(os.path.join(ROOT, name), target)
    for name, content in (("README-macOS.txt", MAC_README),):
        with open(os.path.join(resources, name), "w", encoding="utf-8") as handle:
            handle.write(content)

    launcher = os.path.join(contents, "MacOS", "launcher")
    with open(launcher, "w", encoding="utf-8") as handle:
        handle.write('''#!/bin/bash
DIR="$(cd "$(dirname "$0")/../Resources/app" && pwd)"
cd "$DIR" || exit 1
PY="$(command -v python3 || echo /usr/bin/python3)"
if ! "$PY" -c "import fitz" >/dev/null 2>&1; then
  osascript -e 'display dialog "首次使用请双击包内的 安装依赖.command 安装依赖后再启动。" buttons {"好"}'
  exit 1
fi
exec "$PY" -m webui.server
''')
    os.chmod(launcher, 0o755)

    install = os.path.join(resources, "安装依赖.command")
    with open(install, "w", encoding="utf-8") as handle:
        handle.write(f'''#!/bin/bash
cd "{app_dir}"
python3 -m pip install --user -r crossplatform/requirements.txt
python3 scripts/fetch_engines.py --all || true
echo "完成，可以关闭此窗口并启动 万能转码.app"
read -n 1
''')
    os.chmod(install, 0o755)

    info = {
        "CFBundleName": "万能转码",
        "CFBundleDisplayName": "万能转码",
        "CFBundleIdentifier": "com.inkpaper.anyconvert.web",
        "CFBundleVersion": "1.5.0",
        "CFBundleShortVersionString": "1.5.0",
        "CFBundlePackageType": "APPL",
        "CFBundleExecutable": "launcher",
        "LSMinimumSystemVersion": "11.0",
        "NSHighResolutionCapable": True,
    }
    with open(os.path.join(contents, "Info.plist"), "wb") as handle:
        plistlib.dump(info, handle)

    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", bundle], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    out = os.path.join(DIST, f"AnyConvert-{VERSION}-macOS-web.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for base, _dirs, files in os.walk(bundle):
            for name in files:
                path = os.path.join(base, name)
                archive.write(path, os.path.relpath(path, work))
        archive.writestr("README-macOS.txt", MAC_README)
    shutil.rmtree(work, ignore_errors=True)
    print(f"{os.path.basename(out)}  {os.path.getsize(out)/1024/1024:.1f} MB")


if __name__ == "__main__":
    os.makedirs(DIST, exist_ok=True)
    build_windows()
    build_linux()
    build_macos_app()
