"""本地 Web UI 后端：浏览器里跑的跨平台界面。

启动：
    python3 -m webui.server            # 自动开浏览器
    python3 -m webui.server --no-browser --port 8765
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import shutil
import sys
import tempfile
import threading
import uuid
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from crossplatform.core import engines, pdf_tools  # noqa: E402
from crossplatform.core.matrix import MATRIX  # noqa: E402
from crossplatform.core.queue import ConversionQueue  # noqa: E402
from webui import installer  # noqa: E402

STATIC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")

GROUPS = {
    "文档": ["pdf", "docx", "txt", "md", "html", "odt", "rtf", "xlsx", "csv", "pptx"],
    "图片": ["jpg", "png", "webp", "avif", "tiff", "bmp", "ico"],
    "音频": ["mp3", "m4a", "aac", "wav", "flac", "alac", "ogg", "opus", "wma", "aiff", "ac3", "caf"],
    "视频": ["mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv", "flv", "ts", "mpg", "3gp", "ogv", "gif"],
}

DEFAULT_OPTIONS = {
    "resolution": "original", "width": 0, "height": 0,
    "quality": "balanced", "fps": 0, "audio_kbps": 192, "codec": "h264",
}


class State:
    def __init__(self):
        self.queue = ConversionQueue(max_workers=3)
        self.work = tempfile.mkdtemp(prefix="anyconvert-web-")
        self.options = dict(DEFAULT_OPTIONS)
        self.files: dict[str, str] = {}
        self.lock = threading.Lock()

    def new_path(self, name: str) -> tuple[str, str]:
        token = uuid.uuid4().hex[:10]
        safe = os.path.basename(name) or f"file-{token}"
        folder = os.path.join(self.work, token)
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, safe)
        self.files[token] = path
        return token, path


STATE = State()


def jobs_payload() -> dict:
    jobs = []
    for job in STATE.queue.snapshot():
        jobs.append({
            "id": job["id"],
            "name": os.path.basename(job["src"]),
            "target": job["target"],
            "status": job["status"],
            "progress": job["progress"],
            "error": job["error"],
            "output": os.path.basename(job["output"]) if job["output"] else "",
            "has_output": bool(job["output"] and os.path.exists(job["output"])),
            "elapsed": job.get("elapsed", 0),
        })
    return {"jobs": jobs, "stats": STATE.queue.stats(),
            "max_workers": STATE.queue.max_workers}


class Handler(BaseHTTPRequestHandler):
    server_version = "AnyConvertWeb/1.0"

    # ------------------------------------------------------------ 基础

    def log_message(self, fmt, *args):  # noqa: A003
        pass

    def _json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self) -> bytes:
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def _query(self) -> dict:
        return parse_qs(urlparse(self.path).query)

    def _file(self, path: str, download_name: str | None = None) -> None:
        if not os.path.exists(path):
            self._json({"ok": False, "error": "文件不存在"}, 404)
            return
        size = os.path.getsize(path)
        self.send_response(200)
        self.send_header("Content-Type", mimetypes.guess_type(path)[0] or "application/octet-stream")
        self.send_header("Content-Length", str(size))
        if download_name:
            self.send_header("Content-Disposition", f'attachment; filename="{download_name}"')
        self.end_headers()
        with open(path, "rb") as handle:
            shutil.copyfileobj(handle, self.wfile)

    # ------------------------------------------------------------ GET

    def do_GET(self):  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/api/state":
            status = engines.engine_status()
            targets = {name: {"category": spec.get("category"), "sources": len(spec.get("sources", []))}
                       for name, spec in MATRIX.targets.items()}
            self._json({
                "ok": True,
                "groups": GROUPS,
                "targets": targets,
                "engines": status,
                "options": STATE.options,
                "max_workers": STATE.queue.max_workers,
            })
            return
        if path == "/api/install-status":
            self._json({"ok": True, **installer.STATE})
            return
        if path == "/api/jobs":
            self._json({"ok": True, **jobs_payload()})
            return
        if path == "/api/file/":
            self._json({"ok": False, "error": "missing token"}, 400)
            return
        if path.startswith("/api/file/"):
            token = path.rsplit("/", 1)[-1]
            target = STATE.files.get(token)
            if not target:
                self._json({"ok": False, "error": "链接已失效"}, 404)
                return
            self._file(target, os.path.basename(target))
            return
        if path.startswith("/api/download/"):
            job_id = path.rsplit("/", 1)[-1]
            job = next((j for j in STATE.queue.snapshot() if j["id"] == job_id), None)
            if not job or not job["output"]:
                self._json({"ok": False, "error": "还没有输出"}, 404)
                return
            self._file(job["output"], os.path.basename(job["output"]))
            return
        self._static(path)

    # ------------------------------------------------------------ POST

    def do_POST(self):  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)
        try:
            if path == "/api/upload":
                self._upload(query)
                return
            if path == "/api/temp":
                self._temp(query)
                return
            if path == "/api/start":
                count = STATE.queue.start()
                self._json({"ok": True, "started": count})
                return
            if path == "/api/cancel":
                STATE.queue.cancel()
                self._json({"ok": True})
                return
            if path == "/api/install-libreoffice":
                installer.ensure_async()
                self._json({"ok": True, **installer.STATE})
                return
            if path == "/api/workers":
                data = json.loads(self._body() or b"{}")
                STATE.queue.set_max_workers(int(data.get("value", 3)))
                self._json({"ok": True, "max_workers": STATE.queue.max_workers})
                return
            if path == "/api/options":
                data = json.loads(self._body() or b"{}")
                STATE.options.update({k: v for k, v in data.items() if k in DEFAULT_OPTIONS})
                self._json({"ok": True, "options": STATE.options})
                return
            if path.startswith("/api/reveal/"):
                job_id = path.rsplit("/", 1)[-1]
                job = next((j for j in STATE.queue.snapshot() if j["id"] == job_id), None)
                if job and job["output"]:
                    folder = os.path.dirname(job["output"])
                    if sys.platform == "darwin":
                        os.system(f'open -R "{job["output"]}"')
                    elif os.name == "nt":
                        os.system(f'explorer /select,"{job["output"]}"')
                    else:
                        os.system(f'xdg-open "{folder}"')
                self._json({"ok": True})
                return
            if path.startswith("/api/tool/"):
                self._tool(path.rsplit("/", 1)[-1])
                return
            self._json({"ok": False, "error": "未知接口"}, 404)
        except Exception as exc:  # noqa: BLE001
            self._json({"ok": False, "error": str(exc)}, 500)

    # ------------------------------------------------------------ 上传/工具

    def _upload(self, query: dict) -> None:
        name = (query.get("name") or ["file"])[0]
        target = (query.get("target") or ["mp4"])[0]
        data = self._body()
        token, path = STATE.new_path(name)
        with open(path, "wb") as handle:
            handle.write(data)

        target_bytes = int((query.get("target_bytes") or ["0"])[0] or 0)
        accepted, rejected = STATE.queue.add(
            [path], target, target_bytes or None,
            (query.get("codec") or ["h264"])[0],
            {
                "resolution": (query.get("resolution") or ["original"])[0],
                "width": int((query.get("width") or ["0"])[0] or 0),
                "height": int((query.get("height") or ["0"])[0] or 0),
                "quality": (query.get("quality") or ["balanced"])[0],
                "fps": int((query.get("fps") or ["0"])[0] or 0),
                "audio_kbps": int((query.get("audio_kbps") or ["192"])[0] or 192),
            },
        )
        if rejected:
            self._json({"ok": False, "error": rejected[0].reason}, 200)
            return
        self._json({"ok": True, "token": token, "job": accepted[0].to_dict()})

    def _temp(self, query: dict) -> None:
        name = (query.get("name") or ["file"])[0]
        token, path = STATE.new_path(name)
        with open(path, "wb") as handle:
            handle.write(self._body())
        self._json({"ok": True, "token": token, "name": os.path.basename(path)})

    def _tool(self, name: str) -> None:
        data = json.loads(self._body() or b"{}")
        tokens = data.get("files", [])
        paths = [STATE.files[t] for t in tokens if t in STATE.files]
        if not paths:
            self._json({"ok": False, "error": "没有文件"}, 400)
            return
        base = os.path.splitext(os.path.basename(paths[0]))[0]
        friendly = {
            "merge-pdfs": "merged.pdf",
            "split-pdf": f"{base}-split.zip",
            "pdf-images": f"{base}-images.zip",
            "pdf-tables": f"{base}-tables.xlsx",
            "images-to-pdf": f"{base}.pdf",
            "zip": "archive.zip",
        }.get(name, f"{name}.out")
        token, output = STATE.new_path(friendly)
        if name == "pdf-images":
            output = pdf_tools.pdf_to_images_zip(paths[0], STATE.work, fmt=data.get("format", "png"),
                                                 dpi=int(data.get("dpi", 150)), level=int(data.get("level", 6)))
        elif name == "pdf-tables":
            output = output + ".xlsx"
            pdf_tools.pdf_tables_to_xlsx(paths[0], output)
        elif name == "merge-pdfs":
            output = output + ".pdf"
            pdf_tools.merge_pdfs(paths, output)
        elif name == "split-pdf":
            output = pdf_tools.split_pdf(paths[0], STATE.work, every=int(data.get("every", 1)))
        elif name == "images-to-pdf":
            output = output + ".pdf"
            pdf_tools.images_to_pdf(paths, output)
        elif name == "zip":
            output = output + ".zip"
            engines.zip_files(paths, output, int(data.get("level", 6)))
        else:
            self._json({"ok": False, "error": "未知工具"}, 404)
            return
        token = uuid.uuid4().hex[:10]
        STATE.files[token] = output
        self._json({"ok": True, "download": f"/api/file/{token}", "name": os.path.basename(output)})

    # ------------------------------------------------------------ 静态文件

    def _static(self, path: str) -> None:
        if path in ("/", ""):
            path = "/index.html"
        target = os.path.normpath(os.path.join(STATIC, path.lstrip("/")))
        if not target.startswith(STATIC) or not os.path.isfile(target):
            target = os.path.join(STATIC, "index.html")
        content_type = mimetypes.guess_type(target)[0] or "text/html"
        if content_type.startswith("text/") or content_type == "application/javascript":
            content_type += "; charset=utf-8"
        with open(target, "rb") as handle:
            body = handle.read()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:  # noqa: BLE001
            pass
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args()

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    port = server.server_address[1]
    url = f"http://127.0.0.1:{port}/"
    print(f"万能转码 Web UI: {url}")
    if not args.no_browser:
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
