#!/usr/bin/env python3
"""把转换引擎下载到 crossplatform/vendor/，让软件自带、离线可用。

用法：
    python3 scripts/fetch_engines.py --all
    python3 scripts/fetch_engines.py --libreoffice
    python3 scripts/fetch_engines.py --ffmpeg
"""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENDOR = os.path.join(ROOT, "crossplatform", "vendor")
DOWNLOADS = os.path.join(VENDOR, "downloads")
LO_VERSION = "26.8.2"
LO_BASE = "https://download.documentfoundation.org/libreoffice/stable"


def log(message: str) -> None:
    print(f"[engines] {message}", flush=True)


def download(url: str, target: str) -> str:
    os.makedirs(os.path.dirname(target), exist_ok=True)
    if os.path.exists(target) and os.path.getsize(target) > 1024:
        log(f"已存在，跳过：{target}")
        return target
    log(f"下载 {url}")
    tmp = target + ".part"
    with urllib.request.urlopen(url, timeout=120) as response, open(tmp, "wb") as handle:
        total = int(response.headers.get("Content-Length") or 0)
        done = 0
        while True:
            chunk = response.read(1 << 20)
            if not chunk:
                break
            handle.write(chunk)
            done += len(chunk)
            if total:
                print(f"\r  {done * 100 // total}%  {done >> 20} MiB", end="", flush=True)
    print()
    os.replace(tmp, target)
    return target


def fetch_ffmpeg() -> None:
    script = os.path.join(ROOT, "scripts", "fetch_ffmpeg.sh")
    if os.path.exists(script):
        subprocess.run(["bash", script], check=False)
    else:
        log("未找到 scripts/fetch_ffmpeg.sh，请手动放置 ffmpeg 到 crossplatform/vendor/")


def fetch_libreoffice() -> None:
    system = platform.system()
    machine = platform.machine().lower()
    if system == "Darwin":
        arch = "aarch64" if machine in ("arm64", "aarch64") else "x86-64"
        name = f"LibreOffice_{LO_VERSION}_MacOS_{arch}.dmg"
        url = f"{LO_BASE}/{LO_VERSION}/mac/{arch}/{name}"
        dmg = download(url, os.path.join(DOWNLOADS, "LibreOffice.dmg"))
        mount = "/Volumes/LibreOffice"
        subprocess.run(["hdiutil", "attach", "-nobrowse", "-readonly", dmg], check=True)
        try:
            source = os.path.join(mount, "LibreOffice.app")
            target = os.path.join(VENDOR, "LibreOffice.app")
            if os.path.exists(target):
                shutil.rmtree(target)
            log("复制 LibreOffice.app（约 800 MB）")
            subprocess.run(["cp", "-R", source, VENDOR], check=True)
        finally:
            subprocess.run(["hdiutil", "detach", mount], check=False)
        log(f"完成：{os.path.join(VENDOR, 'LibreOffice.app')}")
        return
    if system == "Linux":
        arch = "x86_64" if machine in ("x86_64", "amd64") else "aarch64"
        name = f"LibreOffice_{LO_VERSION}_Linux_{arch}.tar.gz"
        url = f"{LO_BASE}/{LO_VERSION}/deb/{arch}/{name}"
        archive = download(url, os.path.join(DOWNLOADS, "libreoffice.tar.gz"))
        log(f"解压 {archive} 到 vendor/LibreOffice")
        subprocess.run(["tar", "-xzf", archive, "-C", VENDOR], check=True)
        return
    log("Windows 请下载 LibreOffice 便携版并解压到 crossplatform/vendor/LibreOffice，"
        "确保 vendor/LibreOffice/program/soffice.exe 存在")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--ffmpeg", action="store_true")
    parser.add_argument("--libreoffice", action="store_true")
    args = parser.parse_args()
    if not (args.all or args.ffmpeg or args.libreoffice):
        parser.print_help()
        return 1
    os.makedirs(VENDOR, exist_ok=True)
    if args.all or args.ffmpeg:
        fetch_ffmpeg()
    if args.all or args.libreoffice:
        fetch_libreoffice()
    return 0


if __name__ == "__main__":
    sys.exit(main())
