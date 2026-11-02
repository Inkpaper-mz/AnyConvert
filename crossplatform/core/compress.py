"""按目标体积压缩（图片 / 视频）。

思路
----
图片：对质量做二分（JPEG qscale、WebP quality、AVIF CRF），达不到目标就降分辨率再二分。
视频：由目标体积反推总码率（扣除音频与容器开销），用 x264 两遍编码逼近；
      体积仍超标就按比例二次压缩，最多两次；目标过小时明确失败（TargetUnreachable）。
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import threading
import uuid

from .engines import EngineError, EngineUnavailable, ProgressCallback, _duration, find_ffmpeg, find_ffprobe, unique_output
from .matrix import extension_of, normalize_ext

IMAGE_TARGETS = {"jpg", "jpeg", "png", "webp", "avif"}
VIDEO_TARGETS = {"mp4", "mov", "mkv", "webm", "avi", "ts"}


class TargetUnreachable(EngineError):
    def __init__(self, target_bytes: int, best_bytes: int):
        self.target_bytes = target_bytes
        self.best_bytes = best_bytes

        def mb(value: int) -> str:
            return f"{value / 1024 / 1024:.2f} MB"

        super().__init__(
            f"无法压缩到 {mb(target_bytes)}：当前参数下最小约 {mb(best_bytes)}。"
            f"建议提高目标体积、降低分辨率，或改用更高效的格式。",
            code="E_TARGET_UNREACHABLE",
        )


# ---------------------------------------------------------------- 图片


def compress_image_to_target(src: str, target_bytes: int, out_dir: str,
                             cancel: threading.Event | None = None) -> str:
    ext = extension_of(src)
    if ext not in IMAGE_TARGETS:
        ext = "jpg"
    if ext == "jpeg":
        ext = "jpg"

    work = tempfile.mkdtemp(prefix="anyconvert-img-")
    best_size = 0
    try:
        if ext == "png":
            # PNG 无损：只能靠缩放逼近
            scale = 0.9
            while scale >= 0.1:
                candidate = _encode_image(src, ext, 0, scale, work, cancel)
                best_size = os.path.getsize(candidate) if os.path.exists(candidate) else best_size
                if best_size and best_size <= target_bytes:
                    return _publish(candidate, src, ext, out_dir)
                scale *= 0.8
            raise TargetUnreachable(target_bytes, best_size or 0)

        quality = _search_quality(src, ext, target_bytes, work, cancel)
        if quality is None:
            # 质量到底仍超标：逐级降分辨率再搜
            scale = 0.8
            while scale >= 0.15:
                quality = _search_quality(src, ext, target_bytes, work, cancel, scale=scale)
                if quality is not None:
                    candidate = _encode_image(src, ext, quality, scale, work, cancel)
                    if os.path.getsize(candidate) <= target_bytes:
                        return _publish(candidate, src, ext, out_dir)
                scale *= 0.75
            # 记录最后一次的大小用于报错
            last = _encode_image(src, ext, _worst_quality(ext), 0.15, work, cancel)
            best_size = os.path.getsize(last) if os.path.exists(last) else 0
            raise TargetUnreachable(target_bytes, best_size)

        candidate = _encode_image(src, ext, quality, 1.0, work, cancel)
        if os.path.getsize(candidate) > target_bytes:
            raise TargetUnreachable(target_bytes, os.path.getsize(candidate))
        return _publish(candidate, src, ext, out_dir)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def _worst_quality(ext: str) -> int:
    return {"jpg": 31, "jpeg": 31, "webp": 60, "avif": 45}.get(ext, 31)


def _search_quality(src: str, ext: str, target: int, work: str,
                    cancel: threading.Event | None, scale: float = 1.0) -> int | None:
    """返回满足体积的最大质量；找不到返回 None。"""
    if ext in ("jpg", "jpeg"):
        lo, hi = 2, 31          # qscale 越小质量越高
        best = None
        while lo <= hi:
            mid = (lo + hi) // 2
            path = _encode_image(src, ext, mid, scale, work, cancel)
            if os.path.getsize(path) <= target:
                best = mid
                lo = mid + 1
            else:
                hi = mid - 1
        return best

    if ext == "webp":
        lo, hi = 5, 95
        best = None
        while lo <= hi:
            mid = (lo + hi) // 2
            path = _encode_image(src, ext, mid, scale, work, cancel)
            if os.path.getsize(path) <= target:
                best = mid
                lo = mid + 1
            else:
                hi = mid - 1
        return best

    if ext == "avif":
        lo, hi = 10, 55         # CRF 越大体积越小
        best = None
        while lo <= hi:
            mid = (lo + hi) // 2
            path = _encode_image(src, ext, mid, scale, work, cancel)
            if os.path.getsize(path) <= target:
                best = mid
                hi = mid - 1
            else:
                lo = mid + 1
        return best

    return None


def _encode_image(src: str, ext: str, quality: int, scale: float, work: str,
                  cancel: threading.Event | None) -> str:
    ffmpeg = find_ffmpeg()
    out = os.path.join(work, f"{uuid.uuid4().hex}.{ext}")
    args = [ffmpeg, "-hide_banner", "-nostdin", "-y", "-i", src]
    if scale < 0.999:
        args += ["-vf", f"scale=iw*{scale:.4f}:ih*{scale:.4f}:flags=lanczos"]
    if ext in ("jpg", "jpeg"):
        args += ["-c:v", "mjpeg", "-q:v", str(quality), "-pix_fmt", "yuvj420p"]
    elif ext == "webp":
        args += ["-c:v", "libwebp", "-quality", str(quality), "-pix_fmt", "yuva420p"]
    elif ext == "avif":
        args += ["-c:v", "libaom-av1", "-crf", str(quality), "-b:v", "0", "-still-picture", "1"]
    elif ext == "png":
        args += ["-c:v", "png", "-compression_level", "9"]
    args += ["-frames:v", "1", "-update", "1", out]
    _run(args, cancel)
    return out


def _publish(candidate: str, src: str, ext: str, out_dir: str) -> str:
    out = unique_output(src, ext, out_dir)
    shutil.move(candidate, out)
    return out


# ---------------------------------------------------------------- 视频


def compress_video_to_target(src: str, target_bytes: int, out_dir: str,
                             progress: ProgressCallback | None = None,
                             cancel: threading.Event | None = None,
                             audio_kbps: int = 128) -> str:
    ffmpeg = find_ffmpeg()
    duration = _duration(src)
    if duration <= 0:
        raise EngineError("无法读取视频时长，不能按体积压缩", code="E_DURATION")

    has_audio = _has_audio(src)
    out = unique_output(src, "mp4", out_dir)
    log_prefix = os.path.join(tempfile.gettempdir(), f"anyconvert-2pass-{uuid.uuid4().hex[:8]}")

    video_kbps = _video_bitrate(target_bytes, duration, audio_kbps if has_audio else 0)
    attempts = 0
    last_size = 0

    try:
        while attempts < 3:
            attempts += 1
            _two_pass(src, out, video_kbps, audio_kbps if has_audio else 0,
                      log_prefix, progress, cancel)
            last_size = os.path.getsize(out) if os.path.exists(out) else 0
            if last_size and last_size <= int(target_bytes * 1.02):
                if progress:
                    progress(1.0)
                return out
            if attempts >= 3:
                break
            # 按实际体积回退码率，再压一次
            ratio = target_bytes / max(last_size, 1)
            video_kbps = max(60, int(video_kbps * ratio * 0.92))
            if video_kbps < 60:
                break

        _remove(out)
        raise TargetUnreachable(target_bytes, last_size)
    finally:
        for name in os.listdir(tempfile.gettempdir()):
            if name.startswith(os.path.basename(log_prefix)):
                try:
                    os.remove(os.path.join(tempfile.gettempdir(), name))
                except OSError:
                    pass


def _video_bitrate(target_bytes: int, duration: float, audio_kbps: int) -> int:
    total_kbps = target_bytes * 8 / max(duration, 0.1) / 1000
    overhead = 8  # 容器/mux 余量
    video = int(total_kbps * 0.96) - audio_kbps - overhead
    return max(60, video)


def _two_pass(src: str, out: str, video_kbps: int, audio_kbps: int,
              log_prefix: str, progress: ProgressCallback | None,
              cancel: threading.Event | None) -> None:
    ffmpeg = find_ffmpeg()
    null = os.devnull
    pass1 = [
        ffmpeg, "-hide_banner", "-nostdin", "-y", "-i", src,
        "-c:v", "libx264", "-preset", "medium", "-b:v", f"{video_kbps}k",
        "-pass", "1", "-passlogfile", log_prefix, "-an", "-f", "null", null,
    ]
    _run(pass1, cancel)

    pass2 = [
        ffmpeg, "-hide_banner", "-nostdin", "-y", "-i", src,
        "-c:v", "libx264", "-preset", "medium", "-b:v", f"{video_kbps}k",
        "-pass", "2", "-passlogfile", log_prefix,
        "-maxrate", f"{int(video_kbps * 1.5)}k", "-bufsize", f"{int(video_kbps * 2)}k",
        "-movflags", "+faststart", "-pix_fmt", "yuv420p",
    ]
    if audio_kbps > 0:
        pass2 += ["-c:a", "aac", "-b:a", f"{audio_kbps}k"]
    else:
        pass2 += ["-an"]
    pass2.append(out)

    if progress is None:
        _run(pass2, cancel)
        return

    duration = _duration(src)
    proc = subprocess.Popen(pass2, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    for raw in proc.stdout or []:
        if cancel and cancel.is_set():
            proc.terminate()
            break
        line = raw.decode("utf-8", "replace").strip()
        if line.startswith("out_time_us=") and duration > 0:
            try:
                seconds = int(line.split("=", 1)[1]) / 1_000_000
            except ValueError:
                continue
            progress(min(seconds / duration, 0.99))
    code = proc.wait()
    if code != 0:
        raise EngineError(f"两遍编码失败（退出码 {code}）", code="E_FFMPEG")


def _has_audio(src: str) -> bool:
    probe = find_ffprobe()
    if not probe:
        return False
    try:
        out = subprocess.run(
            [probe, "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=index",
             "-of", "csv=p=0", src],
            capture_output=True, timeout=20,
        ).stdout.decode("utf-8", "replace").strip()
        return bool(out)
    except Exception:  # noqa: BLE001
        return False


# ---------------------------------------------------------------- 工具


def _run(args: list[str], cancel: threading.Event | None) -> None:
    proc = subprocess.Popen(args, stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE, stdin=subprocess.DEVNULL)
    while proc.poll() is None:
        if cancel and cancel.is_set():
            proc.terminate()
            raise EngineError("已取消", code="E_CANCELLED")
        try:
            proc.wait(timeout=0.2)
        except subprocess.TimeoutExpired:
            continue
    if proc.returncode != 0:
        stderr = (proc.stderr.read() if proc.stderr else b"").decode("utf-8", "replace")
        detail = "\n".join([ln for ln in stderr.splitlines() if ln.strip()][-3:])
        raise EngineError(detail or f"命令失败（退出码 {proc.returncode}）", code="E_FFMPEG")


def _remove(path: str) -> None:
    try:
        if os.path.exists(path):
            os.remove(path)
    except OSError:
        pass


def compress_to_target(src: str, target: str, target_bytes: int, out_dir: str,
                       progress: ProgressCallback | None = None,
                       cancel: threading.Event | None = None) -> str:
    ext = normalize_ext(target)
    if ext in IMAGE_TARGETS:
        return compress_image_to_target(src, target_bytes, out_dir, cancel)
    if ext in VIDEO_TARGETS:
        return compress_video_to_target(src, target_bytes, out_dir, progress, cancel)
    raise EngineError("目标体积压缩仅支持图片或视频格式", code="E_TARGET_KIND")
