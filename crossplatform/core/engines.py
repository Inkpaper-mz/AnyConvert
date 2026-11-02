"""底层引擎调度：FFmpeg（音视频/图片）与 LibreOffice Headless（文档/PDF）。

设计原则
--------
- 只负责「一个文件 → 一个输出文件」，并发与校验交给 queue / matrix。
- 每次调用都使用独立临时 profile / 独立输出名，避免并发冲突。
- 找不到引擎时抛 EngineUnavailable，由上层转成可读提示，而不是崩溃。
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import threading
import uuid
from dataclasses import dataclass
from typing import Callable

from .matrix import MATRIX, extension_of, normalize_ext

ProgressCallback = Callable[[float], None]

_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = os.path.abspath(os.path.join(_HERE, "..", ".."))
if getattr(sys, "frozen", False):  # PyInstaller：引擎随包放在 _MEIPASS/crossplatform/vendor
    _REPO_ROOT = getattr(sys, "_MEIPASS", _REPO_ROOT)


class EngineError(RuntimeError):
    def __init__(self, message: str, code: str = "E_ENGINE"):
        super().__init__(message)
        self.code = code


class EngineUnavailable(EngineError):
    def __init__(self, engine: str):
        hint = {
            "ffmpeg": "请安装 ffmpeg（macOS: brew install ffmpeg；Windows: ffmpeg.org 压缩包；Linux: apt install ffmpeg）",
            "libreoffice": "请安装 LibreOffice（https://www.libreoffice.org/download/），或设置环境变量 SOFFICE 指向 soffice 可执行文件",
        }.get(engine, "请安装对应引擎")
        super().__init__(f"{engine} 不可用：{hint}", code="E_NO_ENGINE")
        self.engine = engine


# ---------------------------------------------------------------- 定位


def find_ffmpeg() -> str:
    candidates = [
        os.environ.get("FFMPEG"),
        shutil.which("ffmpeg"),
        os.path.join(_REPO_ROOT, "vendor", "ffmpeg"),
        os.path.join(_REPO_ROOT, "vendor", "ffmpeg.exe"),
        os.path.join(_REPO_ROOT, "vendor", "win", "ffmpeg.exe"),
        os.path.join(_REPO_ROOT, "vendor", "intel", "ffmpeg"),
        os.path.join(_REPO_ROOT, "dist", "万能转码.app", "Contents", "Resources", "bin", "ffmpeg-arm64"),
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "C:\\ffmpeg\\bin\\ffmpeg.exe",
    ]
    for item in candidates:
        if item and os.path.isfile(item) and os.access(item, os.X_OK):
            return item
    raise EngineUnavailable("ffmpeg")


def find_ffprobe() -> str:
    ffmpeg = find_ffmpeg()
    sibling = os.path.join(os.path.dirname(ffmpeg), "ffprobe")
    if os.path.isfile(sibling) and os.access(sibling, os.X_OK):
        return sibling
    for item in [os.environ.get("FFPROBE"), shutil.which("ffprobe")]:
        if item and os.path.isfile(item):
            return item
    return ""


def find_soffice() -> str:
    candidates = [
        os.environ.get("SOFFICE"),
        os.path.join(_REPO_ROOT, "crossplatform", "vendor", "LibreOffice.app",
                     "Contents", "MacOS", "soffice"),
        os.path.join(_REPO_ROOT, "crossplatform", "vendor", "LibreOffice", "program", "soffice"),
        os.path.join(_REPO_ROOT, "crossplatform", "vendor", "LibreOffice", "program", "soffice.exe"),
        shutil.which("soffice"),
        shutil.which("libreoffice"),
        "/Applications/LibreOffice.app/Contents/MacOS/soffice",
        "/usr/bin/soffice",
        "/usr/lib/libreoffice/program/soffice",
        r"C:\Program Files\LibreOffice\program\soffice.exe",
        r"C:\Program Files (x86)\LibreOffice\program\soffice.exe",
    ]
    for item in candidates:
        if item and os.path.isfile(item) and os.access(item, os.X_OK):
            return item
    raise EngineUnavailable("libreoffice")


def find_tesseract() -> str:
    for item in [os.environ.get("TESSERACT"), shutil.which("tesseract"),
                 "/opt/homebrew/bin/tesseract", "/usr/local/bin/tesseract"]:
        if item and os.path.isfile(item) and os.access(item, os.X_OK):
            return item
    raise EngineUnavailable("tesseract")


def engine_status() -> dict:
    from . import ocr as ocr_module
    status = {}
    finders = (("ffmpeg", find_ffmpeg), ("libreoffice", find_soffice),
               ("tesseract", find_tesseract), ("ocr", lambda: ocr_module.available()))
    for name, finder in finders:
        try:
            found = finder()
            path = found if isinstance(found, str) else ("system" if found else "")
            available = bool(found)
        except Exception:  # noqa: BLE001
            path = ""
            available = False
        status[name] = {"available": available, "path": path,
                        "bundled": bool(path and "vendor" in str(path))}
    return status


# ---------------------------------------------------------------- 工具


def unique_output(src: str, target: str, out_dir: str, taken: set[str] | None = None) -> str:
    base = os.path.splitext(os.path.basename(src))[0]
    ext = normalize_ext(target)
    os.makedirs(out_dir, exist_ok=True)
    candidate = os.path.join(out_dir, f"{base}.{ext}")
    index = 1
    while os.path.exists(candidate) or (taken and candidate in taken):
        candidate = os.path.join(out_dir, f"{base} ({index}).{ext}")
        index += 1
    return candidate


def _duration(path: str) -> float:
    probe = find_ffprobe()
    if not probe:
        return 0.0
    try:
        out = subprocess.run(
            [probe, "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
            capture_output=True, timeout=20,
        ).stdout.decode("utf-8", "replace").strip()
        return float(out) if out else 0.0
    except Exception:  # noqa: BLE001
        return 0.0


# ---------------------------------------------------------------- FFmpeg


def ffmpeg_convert(src: str, target: str, out_dir: str,
                   progress: ProgressCallback | None = None,
                   cancel: threading.Event | None = None,
                   codec: str = "h264",
                   options: dict | None = None) -> str:
    ffmpeg = find_ffmpeg()
    out = unique_output(src, target, out_dir)
    ext = normalize_ext(target)

    image_exts = {"jpg", "jpeg", "png", "webp", "avif", "tiff", "tif", "bmp", "ico", "heic", "heif"}
    if extension_of(src) in image_exts and ext in {"mp4", "mov", "mkv", "m4v", "webm"}:
        args = [ffmpeg, "-hide_banner", "-nostdin", "-y",
                "-loop", "1", "-framerate", "30", "-i", src, "-t", "5"]
        args += _ffmpeg_output_args(ext, target, codec, options)
        args.append(out)
        _simple_run(args)
        return out

    args: list[str] = [ffmpeg, "-hide_banner", "-nostdin", "-y", "-i", src]
    args += _ffmpeg_output_args(ext, target, codec, options)
    args.append(out)

    duration = _duration(src)
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    errors: list[str] = []

    try:
        for raw in proc.stdout or []:
            if cancel and cancel.is_set():
                proc.terminate()
                break
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("out_time_us="):
                continue
            if duration <= 0 or progress is None:
                continue
            try:
                seconds = int(line.split("=", 1)[1]) / 1_000_000
            except ValueError:
                continue
            progress(min(seconds / duration, 0.99))
        stderr = (proc.stderr.read() if proc.stderr else b"").decode("utf-8", "replace")
        code = proc.wait()
    except Exception:  # noqa: BLE001
        proc.kill()
        raise

    if cancel and cancel.is_set():
        _cleanup(out)
        raise EngineError("已取消", code="E_CANCELLED")
    if code != 0:
        _cleanup(out)
        detail = "\n".join([ln for ln in stderr.splitlines() if ln.strip()][-3:])
        raise EngineError(detail or f"ffmpeg 退出码 {code}", code="E_FFMPEG")
    if not os.path.exists(out) or os.path.getsize(out) == 0:
        _cleanup(out)
        raise EngineError("输出文件为空", code="E_EMPTY")
    if progress:
        progress(1.0)
    return out


def _ffmpeg_output_args(ext: str, target: str, codec: str = "h264",
                        options: dict | None = None) -> list[str]:
    options = options or {}
    resolution = str(options.get("resolution", "original"))
    height = {"2160": 2160, "1080": 1080, "720": 720, "480": 480, "360": 360}.get(resolution)
    custom_w = int(options.get("width") or 0)
    custom_h = int(options.get("height") or 0)
    fps = int(options.get("fps") or 0)
    audio_kbps = int(options.get("audio_kbps") or 192)
    quality = options.get("quality", "balanced")

    def even(value: int) -> int:
        value = max(16, min(value, 7680))
        return value if value % 2 == 0 else value - 1

    filters: list[str] = []
    if custom_w and custom_h:
        filters.append(f"scale={even(custom_w)}:{even(custom_h)}:flags=lanczos")
    elif height:
        filters.append(f"scale=-2:{height}:flags=lanczos")

    def extra(prefix: list[str]) -> list[str]:
        result = list(prefix)
        if filters:
            result += ["-vf", ",".join(filters)]
        if fps:
            result += ["-r", str(fps)]
        return result
    audio_codecs = {
        "mp3": ["-c:a", "libmp3lame", "-b:a", f"{audio_kbps}k"],
        "m4a": ["-c:a", "aac", "-b:a", f"{audio_kbps}k"],
        "aac": ["-c:a", "aac", "-b:a", f"{audio_kbps}k"],
        "wav": ["-c:a", "pcm_s16le"],
        "flac": ["-c:a", "flac"],
        "ogg": ["-c:a", "libvorbis", "-q:a", "5"],
        "opus": ["-c:a", "libopus", "-b:a", f"{min(audio_kbps, 256)}k"],
        "alac": ["-c:a", "alac"],
        "aiff": ["-c:a", "pcm_s16be"],
        "ac3": ["-c:a", "ac3", "-b:a", "384k"],
        "caf": ["-c:a", "pcm_s16le"],
        "wma": ["-c:a", "wmav2", "-b:a", f"{audio_kbps}k"],
    }
    if ext in audio_codecs:
        return ["-vn"] + audio_codecs[ext]

    if ext == "gif":
        return ["-an", "-vf",
                "fps=12,scale='min(640,iw)':-2:flags=lanczos,split[a][b];"
                "[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5",
                "-loop", "0"]

    if ext in {"jpg", "jpeg", "png", "webp", "avif", "tiff", "bmp", "ico"}:
        codecs = {
            "jpg": ["-c:v", "mjpeg", "-q:v", "4", "-pix_fmt", "yuvj420p"],
            "jpeg": ["-c:v", "mjpeg", "-q:v", "4", "-pix_fmt", "yuvj420p"],
            "png": ["-c:v", "png", "-compression_level", "6", "-pix_fmt", "rgba"],
            "webp": ["-c:v", "libwebp", "-quality", "85", "-pix_fmt", "yuva420p"],
            "avif": ["-c:v", "libaom-av1", "-crf", "28", "-b:v", "0", "-still-picture", "1"],
            "tiff": ["-c:v", "tiff", "-pix_fmt", "rgba", "-compression_algo", "deflate"],
            "bmp": ["-c:v", "bmp", "-pix_fmt", "bgra"],
            "ico": ["-c:v", "png", "-pix_fmt", "rgba"],
        }[ext]
        scale = ["-vf", "scale=256:256:force_original_aspect_ratio=decrease"] if ext == "ico" else []
        return ["-an"] + scale + codecs + ["-frames:v", "1", "-update", "1"]

    crf = {"high": 18, "balanced": 23, "small": 28}.get(quality, 23)
    encoder = {
        "h264": ["-c:v", "libx264", "-preset", "medium", "-crf", str(crf)],
        "h265": ["-c:v", "libx265", "-preset", "medium", "-crf", str(crf + 4)],
        "av1": ["-c:v", "libsvtav1", "-crf", str(crf + 6), "-preset", "8"],
    }.get(codec, ["-c:v", "libx264", "-crf", str(crf)])
    video_codecs = {
        "mp4": extra(encoder + ["-pix_fmt", "yuv420p"]) + ["-c:a", "aac", "-b:a", f"{audio_kbps}k", "-movflags", "+faststart"],
        "mov": extra(encoder + ["-pix_fmt", "yuv420p"]) + ["-c:a", "aac", "-b:a", f"{audio_kbps}k", "-movflags", "+faststart"],
        "mkv": extra(encoder + ["-pix_fmt", "yuv420p"]) + ["-c:a", "aac", "-b:a", f"{audio_kbps}k"],
        "webm": ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1",
                 "-c:a", "libopus", "-b:a", "128k"],
        "avi": ["-c:v", "mpeg4", "-q:v", "4", "-c:a", "libmp3lame", "-b:a", "192k"],
        "wmv": ["-c:v", "wmv2", "-b:v", "4M", "-c:a", "wmav2", "-b:a", "192k"],
        "flv": ["-c:v", "libx264", "-crf", "23", "-c:a", "aac", "-b:a", "192k"],
        "ts": ["-c:v", "libx264", "-crf", "23", "-c:a", "aac", "-b:a", "192k", "-f", "mpegts"],
        "3gp": ["-c:v", "libx264", "-profile:v", "baseline", "-crf", "26",
                "-c:a", "aac", "-b:a", "128k"],
        "m4v": encoder + ["-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"],
        "mpg": ["-c:v", "mpeg2video", "-q:v", "4", "-c:a", "mp2", "-b:a", "192k"],
        "ogv": ["-c:v", "libtheora", "-q:v", "6", "-c:a", "libvorbis", "-q:a", "5"],
    }
    return video_codecs.get(ext, extra(["-c:v", "libx264", "-crf", str(crf)]) + ["-c:a", "aac"])


# ---------------------------------------------------------------- LibreOffice


def libreoffice_convert(src: str, target: str, out_dir: str,
                        timeout: int = 300,
                        cancel: threading.Event | None = None) -> str:
    soffice = find_soffice()
    os.makedirs(out_dir, exist_ok=True)
    profile = os.path.join(tempfile.gettempdir(), f"anyconvert-lo-{uuid.uuid4().hex[:8]}")
    work = tempfile.mkdtemp(prefix="anyconvert-lo-out-")
    args = [
        soffice, "--headless", "--norestore", "--nolockcheck", "--nodefault",
        f"-env:UserInstallation=file://{profile}",
        "--convert-to", normalize_ext(target),
        "--outdir", work, src,
    ]
    try:
        proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        while proc.poll() is None:
            if cancel and cancel.is_set():
                proc.terminate()
                raise EngineError("已取消", code="E_CANCELLED")
            try:
                proc.wait(timeout=0.2)
            except subprocess.TimeoutExpired:
                continue
        out, err = proc.communicate()
        if proc.returncode != 0:
            raise EngineError((err or out or b"").decode("utf-8", "replace")[-500:] or "LibreOffice 转换失败",
                              code="E_LO")
        produced = [
            os.path.join(work, name) for name in os.listdir(work)
            if name.lower().endswith("." + normalize_ext(target)) and os.path.getsize(os.path.join(work, name)) > 0
        ]
        if not produced:
            raise EngineError("LibreOffice 没有生成输出文件", code="E_LO")
        produced.sort(key=os.path.getmtime, reverse=True)
        destination = unique_output(src, normalize_ext(target), out_dir)
        shutil.move(produced[0], destination)
        return destination
    finally:
        shutil.rmtree(profile, ignore_errors=True)
        shutil.rmtree(work, ignore_errors=True)

def pdf_to_docx(src: str, out_dir: str) -> str | None:
    """PDF → DOCX 优先用 pdf2docx（版面还原远好于 LibreOffice 的 PDF 导入）。

    未安装 pdf2docx 时返回 None，由调用方回退 LibreOffice。
    """
    try:
        from pdf2docx import Converter  # type: ignore
    except Exception:  # noqa: BLE001
        return None
    out = unique_output(src, "docx", out_dir)
    converter = Converter(src)
    try:
        converter.convert(out)
    finally:
        try:
            converter.close()
        except Exception:  # noqa: BLE001
            pass
    if os.path.exists(out) and os.path.getsize(out) > 0:
        return out
    _cleanup(out)
    return None


def convert(src: str, target: str, out_dir: str,
            progress: ProgressCallback | None = None,
            cancel: threading.Event | None = None,
            target_bytes: int | None = None,
            codec: str = "h264",
            options: dict | None = None) -> str:
    check = MATRIX.validate(target, src)
    if not check.ok:
        raise EngineError(check.reason, code="E_INVALID")
    if target_bytes:
        from .compress import compress_to_target
        return compress_to_target(src, target, target_bytes, out_dir, progress, cancel)
    if normalize_ext(target) == "docx" and extension_of(src) == "pdf":
        converted = pdf_to_docx(src, out_dir)
        if converted:
            return converted
    engine = MATRIX.choose_engine(target, src)
    if engine == "pymupdf":
        return _pymupdf_convert(src, target, out_dir)
    if engine == "zip":
        return zip_files([src], os.path.join(out_dir, os.path.splitext(os.path.basename(src))[0] + ".zip"))
    if engine == "tesseract":
        from . import ocr
        out = unique_output(src, "txt", out_dir)
        with open(out, "w", encoding="utf-8") as handle:
            handle.write(ocr.ocr_image(src))
        return out
    if engine == "libreoffice":
        return libreoffice_convert(src, target, out_dir, cancel=cancel)
    return ffmpeg_convert(src, target, out_dir, progress=progress, cancel=cancel,
                          codec=codec, options=options)


def _cleanup(path: str) -> None:
    try:
        if os.path.exists(path):
            os.remove(path)
    except OSError:
        pass


# ---------------------------------------------------------------- PDF / ZIP / OCR


def _simple_run(args: list[str], timeout: int = 600) -> None:
    result = subprocess.run(args, capture_output=True, timeout=timeout)
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", "replace").strip()
        raise EngineError(detail[-400:] or f"命令失败（退出码 {result.returncode}）", code="E_FFMPEG")


def _pymupdf_convert(src: str, target: str, out_dir: str) -> str:
    from . import pdf_tools

    ext = normalize_ext(target)
    out = unique_output(src, ext, out_dir)
    if ext == "pdf":
        return pdf_tools.images_to_pdf([src], out)
    if ext in ("png", "jpg", "jpeg"):
        images = pdf_tools.pdf_to_images(src, out_dir, fmt="jpg" if ext == "jpeg" else ext)
        if images:
            shutil.move(images[0], out)
            for extra in images[1:]:
                _cleanup(extra)
        return out
    if ext == "txt":
        with open(out, "w", encoding="utf-8") as handle:
            handle.write(pdf_tools.pdf_to_text_ocr(src))
        return out
    if ext == "html":
        with open(out, "w", encoding="utf-8") as handle:
            handle.write(pdf_tools.pdf_to_html(src))
        return out
    raise EngineError(f"不支持的 PDF 输出：.{ext}", code="E_PDF_TARGET")


def zip_files(paths: list[str], output: str, compression_level: int = 6) -> str:
    import zipfile
    os.makedirs(os.path.dirname(output) or ".", exist_ok=True)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=compression_level) as archive:
        for path in paths:
            archive.write(path, os.path.basename(path))
    return output


def _ocr_to_text(src: str, out_dir: str) -> str:
    binary = find_tesseract()
    out = unique_output(src, "txt", out_dir)
    result = subprocess.run([binary, src, "stdout", "-l", "chi_sim+eng"], capture_output=True)
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", "replace").strip()
        raise EngineError(detail or "OCR 失败", code="E_OCR")
    with open(out, "w", encoding="utf-8") as handle:
        handle.write(result.stdout.decode("utf-8", "replace"))
    return out
