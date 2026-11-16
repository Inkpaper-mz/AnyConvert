"""跨平台 PDF 工具：PDFium 渲染、pypdf 页面操作和 pdfplumber 表格提取。"""
from __future__ import annotations

import html
import os
import tempfile
import zipfile


class PdfUnavailable(RuntimeError):
    pass


def _pdfium():
    try:
        import pypdfium2
        return pypdfium2
    except ImportError as exc:
        raise PdfUnavailable("PDF 渲染与文字提取需要 pypdfium2") from exc


def _pypdf():
    try:
        from pypdf import PdfReader, PdfWriter
        return PdfReader, PdfWriter
    except ImportError as exc:
        raise PdfUnavailable("PDF 合并与拆分需要 pypdf") from exc


def _pillow():
    try:
        from PIL import Image
        return Image
    except ImportError as exc:
        raise PdfUnavailable("图片转 PDF 需要 Pillow") from exc


def pdf_to_images(src: str, out_dir: str, fmt: str = "png", dpi: int = 150) -> list[str]:
    if fmt.lower() not in ("png", "jpg", "jpeg") or not 1 <= dpi <= 1200:
        raise ValueError("仅支持 PNG/JPG 和 1–1200 DPI")
    pdfium = _pdfium()
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.splitext(os.path.basename(src))[0]
    outputs = []
    doc = pdfium.PdfDocument(src)
    try:
        for index in range(len(doc)):
            page = doc[index]
            try:
                bitmap = page.render(scale=dpi / 72)
                try:
                    image = bitmap.to_pil()
                    path = os.path.join(out_dir, f"{base}-{index + 1:02d}.{fmt}")
                    image.save(path, format="JPEG" if fmt.lower() in ("jpg", "jpeg") else "PNG")
                    outputs.append(path)
                finally:
                    bitmap.close()
            finally:
                page.close()
    finally:
        doc.close()
    return outputs


def _page_text(page) -> str:
    textpage = page.get_textpage()
    try:
        return textpage.get_text_bounded().strip()
    finally:
        textpage.close()


def pdf_to_text(src: str) -> str:
    pdfium = _pdfium()
    parts = []
    doc = pdfium.PdfDocument(src)
    try:
        for page in doc:
            try:
                parts.append(_page_text(page))
            finally:
                page.close()
    finally:
        doc.close()
    return "\n".join(parts).strip()


def pdf_to_text_ocr(src: str, dpi: int = 200) -> str:
    """逐页提取文本；无文字层页面回退 OCR，保留页序。"""
    from . import ocr
    pdfium = _pdfium()
    parts = []
    with tempfile.TemporaryDirectory(prefix="anyconvert-ocr-") as work:
        doc = pdfium.PdfDocument(src)
        try:
            for index, page in enumerate(doc):
                try:
                    text = _page_text(page)
                    if not text:
                        image = os.path.join(work, f"page-{index + 1}.png")
                        bitmap = page.render(scale=dpi / 72)
                        try:
                            bitmap.to_pil().save(image, format="PNG")
                        finally:
                            bitmap.close()
                        text = ocr.ocr_image(image).strip()
                    parts.append(text)
                finally:
                    page.close()
        finally:
            doc.close()
    return "\n".join(parts).strip()


def pdf_to_html(src: str) -> str:
    # 保留文字和换行；PDFium 不提供等价的原始版面 HTML 导出。
    text = pdf_to_text(src)
    return '<!doctype html><html><head><meta charset="utf-8"></head><body><pre>' + html.escape(text) + '</pre></body></html>'


def merge_pdfs(paths: list[str], output: str) -> str:
    _, PdfWriter = _pypdf()
    writer = PdfWriter()
    try:
        for path in paths:
            writer.append(path)
        with open(output, "wb") as handle:
            writer.write(handle)
    finally:
        writer.close()
    return output


def split_pdf(src: str, out_dir: str, every: int = 1) -> str:
    PdfReader, PdfWriter = _pypdf()
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.splitext(os.path.basename(src))[0]
    outputs = []
    reader = PdfReader(src)
    total = len(reader.pages)
    if not total:
        raise ValueError("PDF 没有页面")
    step = max(1, int(every))
    for start in range(0, total, step):
        end = min(start + step, total)
        writer = PdfWriter()
        try:
            for page in reader.pages[start:end]:
                writer.add_page(page)
            path = os.path.join(out_dir, f"{base}-{start + 1:03d}-{end:03d}.pdf")
            with open(path, "wb") as handle:
                writer.write(handle)
        finally:
            writer.close()
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
    Image = _pillow()
    if not paths:
        raise ValueError("请选择图片")
    images = []
    try:
        for path in paths:
            with Image.open(path) as source:
                if "A" in source.getbands() or "transparency" in source.info:
                    rgba = source.convert("RGBA")
                    background = Image.new("RGB", rgba.size, "white")
                    background.paste(rgba, mask=rgba.getchannel("A"))
                    rgba.close()
                    images.append(background)
                else:
                    images.append(source.convert("RGB"))
        images[0].save(output, format="PDF", save_all=True, append_images=images[1:])
    finally:
        for image in images:
            image.close()
    return output


def pdf_page_count(src: str) -> int:
    PdfReader, _ = _pypdf()
    return len(PdfReader(src).pages)


def pdf_to_images_zip(src: str, out_dir: str, fmt: str = "png", dpi: int = 150, level: int = 6) -> str:
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.splitext(os.path.basename(src))[0]
    archive = os.path.join(out_dir, f"{base}-images.zip")
    with tempfile.TemporaryDirectory(prefix="anyconvert-pdf-images-") as work:
        images = pdf_to_images(src, work, fmt=fmt, dpi=dpi)
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=max(0, min(9, level))) as zf:
            for path in images:
                zf.write(path, os.path.basename(path))
    return archive


def pdf_tables_to_xlsx(src: str, output: str) -> str:
    try:
        import pdfplumber
        from openpyxl import Workbook
    except ImportError as exc:
        raise PdfUnavailable("PDF 表格提取需要 pdfplumber 和 openpyxl") from exc
    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "Tables"
    found = 0
    with pdfplumber.open(src) as doc:
        for page in doc.pages:
            for table in page.extract_tables():
                for line in table:
                    sheet.append([str(value) if value is not None else None for value in line])
                    # 源 PDF 是数据，不能让以 = 开头的内容变成 Excel 公式。
                    for cell in sheet[sheet.max_row]:
                        if cell.value is not None:
                            cell.data_type = "s"
                sheet.append([])
                found += 1
    if found == 0:
        raise RuntimeError("未在该 PDF 中检测到表格（扫描件请先 OCR）")
    workbook.save(output)
    return output
