"""OCR：macOS 用系统 Vision（零依赖、中文效果好），其他平台回退 Tesseract。"""

from __future__ import annotations

import shutil
import subprocess
import sys


class OcrUnavailable(RuntimeError):
    pass


def available() -> bool:
    if sys.platform == "darwin":
        try:
            import Vision  # noqa: F401
            return True
        except Exception:  # noqa: BLE001
            pass
    return shutil.which("tesseract") is not None


def ocr_image(src: str) -> str:
    if sys.platform == "darwin":
        try:
            return _vision_ocr(src)
        except Exception:  # noqa: BLE001
            pass
    return _tesseract_ocr(src)


def _vision_ocr(path: str) -> str:
    import Vision
    from Foundation import NSURL

    url = NSURL.fileURLWithPath_(path)
    request = Vision.VNRecognizeTextRequest.alloc().init()
    request.setRecognitionLevel_(0)  # accurate
    request.setUsesLanguageCorrection_(True)
    request.setRecognitionLanguages_(["zh-Hans", "en-US"])
    handler = Vision.VNImageRequestHandler.alloc().initWithURL_options_(url, None)
    handler.performRequests_error_([request], None)

    lines: list[str] = []
    for observation in request.results() or []:
        candidates = observation.topCandidates_(1)
        if candidates and len(candidates) > 0:
            lines.append(str(candidates[0].string()))
    if not lines:
        raise OcrUnavailable("未识别到文字")
    return "\n".join(lines)


def _tesseract_ocr(path: str) -> str:
    binary = shutil.which("tesseract")
    if not binary:
        raise OcrUnavailable("需要 Tesseract：macOS 自带 Vision 不可用时请安装 tesseract")
    result = subprocess.run([binary, path, "stdout", "-l", "chi_sim+eng"], capture_output=True)
    if result.returncode != 0:
        raise OcrUnavailable(result.stderr.decode("utf-8", "replace").strip() or "OCR 失败")
    return result.stdout.decode("utf-8", "replace")
