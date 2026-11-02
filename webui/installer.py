"""首次运行下载 LibreOffice（清华 TUNA 镜像，分段并发）。

安装位置（用户目录，无需管理员）：
- macOS:   ~/Library/Application Support/AnyConvert/LibreOffice.app
- Windows: %LOCALAPPDATA%\\AnyConvert\\LibreOffice
- Linux:   ~/.local/share/AnyConvert/LibreOffice
"""

from __future__ import annotations

import os
import platform
import shutil
import subprocess
import tarfile
import tempfile
import threading
import urllib.request

VERSION = "26.8.2"
BASE = f"https://mirrors.tuna.tsinghua.edu.cn/libreoffice/libreoffice/stable/{VERSION}"
PARTS = 8

STATE = {"state": "idle", "progress": 0.0, "message": ""}
LOCK = threading.Lock()


def target_root() -> str:
    system = platform.system()
    if system == "Darwin":
        return os.path.expanduser("~/Library/Application Support/AnyConvert")
    if system == "Windows":
        return os.path.join(os.environ.get("LOCALAPPDATA", os.path.expanduser("~")), "AnyConvert")
    return os.path.expanduser("~/.local/share/AnyConvert")


def soffice_path() -> str:
    root = target_root()
    candidates = [
        os.path.join(root, "LibreOffice.app", "Contents", "MacOS", "soffice"),
        os.path.join(root, "LibreOffice", "program", "soffice"),
        os.path.join(root, "LibreOffice", "program", "soffice.exe"),
        os.path.join(root, "LibreOffice", "program", "soffice.bin"),
    ]
    for path in candidates:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    return ""


def _set(state: str, progress: float, message: str) -> None:
    with LOCK:
        STATE.update(state=state, progress=max(0.0, min(1.0, progress)), message=message)


def _url() -> str:
    system = platform.system()
    machine = platform.machine().lower()
    arch = "aarch64" if machine in ("arm64", "aarch64") else "x86-64"
    if system == "Darwin":
        return f"{BASE}/mac/{arch}/LibreOffice_{VERSION}_MacOS_{arch}.dmg"
    if system == "Windows":
        return f"{BASE}/win/x86_64/LibreOffice_{VERSION}_Win_x86-64.msi"
    return f"{BASE}/deb/x86_64/LibreOffice_{VERSION}_Linux_x86_64.tar.gz"


def _download(url: str, dest: str, progress) -> None:
    request = urllib.request.Request(url, method="HEAD")
    with urllib.request.urlopen(request, timeout=60) as response:
        total = int(response.headers.get("Content-Length") or 0)
    if total <= 0:
        raise RuntimeError("无法获取文件大小")
    chunk = (total + PARTS - 1) // PARTS
    parts = []
    done = [0] * PARTS

    def fetch(index: int) -> None:
        start = index * chunk
        end = min(start + chunk, total) - 1
        path = f"{dest}.part{index}"
        parts.append(path)
        req = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}"})
        with urllib.request.urlopen(req, timeout=120) as response, open(path, "wb") as handle:
            while True:
                block = response.read(1 << 20)
                if not block:
                    break
                handle.write(block)
                done[index] += len(block)
                progress(sum(done) / total * 0.85)

    threads = [threading.Thread(target=fetch, args=(i,)) for i in range(PARTS)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    with open(dest, "wb") as output:
        for index in range(PARTS):
            path = f"{dest}.part{index}"
            with open(path, "rb") as handle:
                shutil.copyfileobj(handle, output)
            os.remove(path)
    if os.path.getsize(dest) != total:
        raise RuntimeError("下载文件不完整")


def _install_macos(archive: str, progress) -> None:
    mount = "/Volumes/LibreOffice"
    subprocess.run(["hdiutil", "attach", "-nobrowse", "-readonly", archive], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        source = os.path.join(mount, "LibreOffice.app")
        destination = os.path.join(target_root(), "LibreOffice.app")
        if os.path.exists(destination):
            shutil.rmtree(destination)
        os.makedirs(target_root(), exist_ok=True)
        progress(0.9)
        subprocess.run(["cp", "-R", source, target_root()], check=True)
    finally:
        subprocess.run(["hdiutil", "detach", mount], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _install_windows(archive: str, progress) -> None:
    destination = os.path.join(target_root(), "LibreOffice")
    os.makedirs(destination, exist_ok=True)
    progress(0.9)
    subprocess.run(["msiexec", "/a", archive, "/qn", f"TARGETDIR={destination}", "/norestart"],
                   check=True)
    for root, _dirs, files in os.walk(destination):
        if "soffice.exe" in files:
            return
    raise RuntimeError("LibreOffice 解包失败")


def _install_linux(archive: str, progress) -> None:
    destination = os.path.join(target_root())
    os.makedirs(destination, exist_ok=True)
    with tarfile.open(archive, "r:gz") as tar:
        tar.extractall(destination)
    for root, _dirs, files in os.walk(destination):
        if "soffice" in files:
            return
    raise RuntimeError("LibreOffice 解压失败")


def install() -> None:
    if STATE["state"] == "running":
        return
    _set("running", 0.0, "准备下载…")
    work = tempfile.mkdtemp(prefix="anyconvert-lo-")
    archive = os.path.join(work, "libreoffice-download")
    try:
        _download(_url(), archive, lambda p: _set("running", p, f"下载中 {int(p * 100)}%"))
        _set("running", 0.88, "正在安装…")
        system = platform.system()
        if system == "Darwin":
            _install_macos(archive, lambda p: _set("running", p, "正在复制 LibreOffice…"))
        elif system == "Windows":
            _install_windows(archive, lambda p: _set("running", p, "正在解包 LibreOffice…"))
        else:
            _install_linux(archive, lambda p: _set("running", p, "正在解压 LibreOffice…"))
        if not soffice_path():
            raise RuntimeError("安装完成但未找到 soffice")
        _set("done", 1.0, "LibreOffice 已就绪")
    except Exception as exc:  # noqa: BLE001
        _set("failed", 0.0, str(exc))
    finally:
        shutil.rmtree(work, ignore_errors=True)


def ensure_async() -> None:
    threading.Thread(target=install, daemon=True).start()
