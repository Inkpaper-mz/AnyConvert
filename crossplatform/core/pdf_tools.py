"""PDF 专项能力（PyMuPDF）：渲染、取文本、合并、拆分、图片转 PDF。

不依赖外部二进制，跨平台一致；没装 pymupdf 时给出可读提示。
"""

from __future__ import annotations

import os
import shutil
import tempfile
import zipfile

try:
    import fitz  # PyMuPDF
except Exception:  # noqa: BLE001
    fitz = None


class PdfUnavailable(RuntimeError):
    pass


def _require():
    if fitz is None:
        raise PdfUnavailable("PDF 功能需要 PyMuPDF：python3 -m pip install --user pymupdf")


def pdf_to_images(src: str, out_dir: str, fmt: str = "png", dpi: int = 150) -> list[str]:
    """把 PDF 每一页渲染成图片，返回文件列表。"""
    _require()
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.splitext(os.path.basename(src))[0]
    outputs = []
    with fitz.open(src) as doc:
        for index, page in enumerate(doc):
            zoom = dpi / 72
            matrix = fitz.Matrix(zoom, zoom)
            pixmap = page.get_pixmap(matrix=matrix, alpha=False)
            path = os.path.join(out_dir, f"{base}-{index + 1:02d}.{fmt}")
            pixmap.save(path)
            outputs.append(path)
    return outputs


def pdf_to_text(src: str) -> str:
    _require()
    parts = []
    with fitz.open(src) as doc:
        for page in doc:
            parts.append(page.get_text("text"))
    return "\n".join(parts).strip()


def pdf_to_text_ocr(src: str, dpi: int = 200) -> str:
    """文字型 PDF 直接取文本；扫描件回退 OCR。"""
    text = pdf_to_text(src)
    if text.strip():
        return text
    from . import ocr

    work = tempfile.mkdtemp(prefix="anyconvert-ocr-")
    try:
        pages = pdf_to_images(src, work, fmt="png", dpi=dpi)
        parts = [ocr.ocr_image(page) for page in pages]
        return "\n".join(parts).strip()
    finally:
        shutil.rmtree(work, ignore_errors=True)


def pdf_to_html(src: str) -> str:
    _require()
    parts = []
    with fitz.open(src) as doc:
        for page in doc:
            parts.append(page.get_text("html"))
    return "\n<hr/>\n".join(parts)


def merge_pdfs(paths: list[str], output: str) -> str:
    _require()
    merged = fitz.open()
    try:
        for path in paths:
            with fitz.open(path) as doc:
                merged.insert_pdf(doc)
        merged.save(output)
    finally:
        merged.close()
    return output


def split_pdf(src: str, out_dir: str, every: int = 1) -> str:
    """按每 N 页拆分，输出 zip（单页多文件时）。"""
    _require()
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.splitext(os.path.basename(src))[0]
    outputs = []
    with fitz.open(src) as doc:
        total = doc.page_count
        step = max(1, int(every))
        for start in range(0, total, step):
            end = min(start + step, total)
            part = fitz.open()
            part.insert_pdf(doc, from_page=start, to_page=end - 1)
            name = f"{base}-{start + 1:03d}-{end:03d}.pdf"
            path = os.path.join(out_dir, name)
            part.save(path)
            part.close()
            outputs.append(path)
    if len(outputs) == 1:
        return outputs[0]
    archive = os.path.join(out_dir, f"{base}-split.zip")
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in outputs:
            zf.write(path, os.path.basename(path))
            os.remove(path)
    return archive


def images_to_pdf(paths: list[str], output: str) -> str:
    _require()
    doc = fitz.open()
    try:
        for path in paths:
            with fitz.open(path) as img:
                rect = img[0].rect
                page = doc.new_page(width=rect.width, height=rect.height)
                page.insert_image(page.rect, filename=path, keep_proportion=True)
        doc.save(output)
    finally:
        doc.close()
    return output


def pdf_page_count(src: str) -> int:
    _require()
    with fitz.open(src) as doc:
        return doc.page_count


def pdf_to_images_zip(src: str, out_dir: str, fmt: str = "png", dpi: int = 150,
                      level: int = 6) -> str:
    """PDF 每页导出图片并打包为 ZIP。"""
    images = pdf_to_images(src, out_dir, fmt=fmt, dpi=dpi)
    base = os.path.splitext(os.path.basename(src))[0]
    archive = os.path.join(out_dir, f"{base}-images.zip")
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=max(0, min(9, level))) as zf:
        for path in images:
            zf.write(path, os.path.basename(path))
            os.remove(path)
    return archive


def pdf_tables_to_xlsx(src: str, output: str) -> str:
    """提取 PDF 中的表格写入 xlsx（PyMuPDF find_tables + openpyxl）。"""
    _require()
    try:
        from openpyxl import Workbook
    except Exception as exc:  # noqa: BLE001
        raise RuntimeError("需要 openpyxl：python3 -m pip install --user openpyxl") from exc

    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "Tables"
    row = 1
    found = 0
    with fitz.open(src) as doc:
        for page in doc:
            try:
                tables = page.find_tables()
            except Exception:  # noqa: BLE001
                continue
            for table in tables:
                for line in table.extract():
                    for column, value in enumerate(line, start=1):
                        sheet.cell(row=row, column=column, value=value)
                    row += 1
                row += 1
                found += 1
    if found == 0:
        raise RuntimeError("未在该 PDF 中检测到表格（扫描件请先 OCR）")
    workbook.save(output)
    return output
