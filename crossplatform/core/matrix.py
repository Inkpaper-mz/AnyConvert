"""转换矩阵：目标格式 → 允许的源格式白名单 + 引擎选择。

设计要点
--------
- 矩阵是纯数据（matrix.json），校验是纯函数，UI 与队列共用同一份规则。
- 引擎选择不只看目标格式：文档/PDF 相关流程必须走 LibreOffice，
  即使目标是 png（PDF 转图）或来源是 pdf（PDF 转 Word）。
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import Iterable

_HERE = os.path.dirname(os.path.abspath(__file__))
MATRIX_PATH = os.path.join(_HERE, "matrix.json")

_ALIASES = {
    "jpeg": "jpg",
    "tif": "tiff",
    "htm": "html",
    "markdown": "md",
    "mpeg": "mpg",
    "aif": "aiff",
}

# 这些扩展名意味着「文档/PDF 语义」，优先交给 LibreOffice
DOCUMENT_EXTENSIONS = {
    "pdf", "docx", "doc", "odt", "rtf", "txt", "md", "html", "epub", "wps", "ofd",
}


@dataclass(frozen=True)
class ValidationResult:
    ok: bool
    target: str
    source_ext: str
    reason: str = ""

    @property
    def message(self) -> str:
        return self.reason


class ConversionMatrix:
    def __init__(self, path: str = MATRIX_PATH):
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        self.version: int = int(data.get("version", 1))
        self.targets: dict[str, dict] = data["targets"]

    # ---- 查询 -------------------------------------------------
    def target_list(self) -> list[str]:
        return list(self.targets.keys())

    def spec(self, target: str) -> dict:
        key = normalize_ext(target)
        if key not in self.targets:
            raise KeyError(f"未知目标格式：.{key}")
        return self.targets[key]

    def sources(self, target: str) -> list[str]:
        return list(self.spec(target).get("sources", []))

    def category(self, target: str) -> str:
        return self.spec(target).get("category", "unknown")

    def supports(self, target: str, source_path: str) -> bool:
        return self.validate(target, source_path).ok

    # ---- 校验（UI 拖拽 / 队列提交都必须先调用）------------------
    def validate(self, target: str, source_path: str) -> ValidationResult:
        target_ext = normalize_ext(target)
        source_ext = extension_of(source_path)

        if target_ext not in self.targets:
            return ValidationResult(False, target_ext, source_ext,
                                    f"未知的目标格式 .{target_ext}。")

        allowed = set(self.sources(target_ext))
        if "*" in allowed:
            allowed = allowed | {source_ext}
        if not source_ext:
            return ValidationResult(False, target_ext, source_ext,
                                    "无法识别文件类型（缺少扩展名）。")
        if source_ext not in allowed:
            return ValidationResult(
                False, target_ext, source_ext,
                f"不支持将 .{source_ext} 转换为 .{target_ext}，请检查文件类型。",
            )
        if not os.path.exists(source_path):
            return ValidationResult(False, target_ext, source_ext,
                                    f"文件不存在：{source_path}")
        if not os.path.isfile(source_path):
            return ValidationResult(False, target_ext, source_ext,
                                    f"不是文件：{source_path}")
        if os.path.getsize(source_path) == 0:
            return ValidationResult(False, target_ext, source_ext,
                                    f"文件为空：{os.path.basename(source_path)}")
        return ValidationResult(True, target_ext, source_ext)

    def validate_many(self, target: str, paths: Iterable[str]) -> tuple[list[str], list[ValidationResult]]:
        """返回 (通过列表, 拒绝结果列表)。"""
        accepted: list[str] = []
        rejected: list[ValidationResult] = []
        for path in paths:
            result = self.validate(target, path)
            if result.ok:
                accepted.append(path)
            else:
                rejected.append(result)
        return accepted, rejected

    # ---- 引擎选择 ---------------------------------------------
    def choose_engine(self, target: str, source_path: str) -> str:
        target_ext = normalize_ext(target)
        source_ext = extension_of(source_path)
        image_exts = {"jpg", "jpeg", "png", "webp", "avif", "tiff", "tif", "bmp", "ico", "gif", "heic", "heif"}

        if target_ext == "zip":
            return "zip"
        if target_ext == "pdf":
            return "pymupdf" if source_ext in image_exts else "libreoffice"
        if target_ext in ("png", "jpg", "jpeg") and source_ext == "pdf":
            return "pymupdf"
        if target_ext == "txt" and source_ext == "pdf":
            return "pymupdf"
        if target_ext == "html" and source_ext == "pdf":
            return "pymupdf"
        if target_ext == "txt" and source_ext in image_exts:
            return "tesseract"

        declared = self.spec(target_ext).get("engine", "ffmpeg")
        if declared == "libreoffice":
            return "libreoffice"
        if source_ext in DOCUMENT_EXTENSIONS or source_ext in {"xls", "xlsx", "ods", "ppt", "pptx", "odp", "csv"}:
            return "libreoffice"
        return declared


def normalize_ext(value: str) -> str:
    ext = value.strip().lower().lstrip(".")
    if "/" in ext or "\\" in ext:  # 传进来的是路径
        ext = os.path.splitext(ext)[1].lstrip(".")
    return _ALIASES.get(ext, ext)


def extension_of(path: str) -> str:
    return normalize_ext(os.path.splitext(path)[1])


MATRIX = ConversionMatrix()
