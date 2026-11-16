import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

try:
    from reportlab.pdfgen import canvas
    import pypdfium2
except ImportError:
    canvas = None

from crossplatform.core import engines, pdf_tools


def make_pdf(directory, name="a.pdf", pages=2):
    path = os.path.join(directory, name)
    doc = canvas.Canvas(path)
    for index in range(pages):
        doc.drawString(72, 720, f"hello page {index + 1}")
        doc.showPage()
    doc.save()
    return path


@unittest.skipIf(canvas is None, "PDF test dependencies not installed")
class PdfTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.out = tempfile.mkdtemp()
        self.pdf = make_pdf(self.tmp, pages=3)

    def test_pdf_to_text(self):
        text = pdf_tools.pdf_to_text(self.pdf)
        self.assertIn("hello page 1", text)
        self.assertEqual(pdf_tools.pdf_page_count(self.pdf), 3)

    def test_ocr_runs_for_scanned_pages_in_mixed_pdf(self):
        path = os.path.join(self.tmp, "mixed.pdf")
        doc = canvas.Canvas(path)
        doc.drawString(72, 720, "first page")
        doc.showPage()
        doc.showPage()
        doc.drawString(72, 720, "third page")
        doc.showPage()
        doc.save()
        with mock.patch("crossplatform.core.ocr.ocr_image", return_value="scanned page") as ocr:
            text = pdf_tools.pdf_to_text_ocr(path, dpi=72)
        self.assertEqual(text, "first page\nscanned page\nthird page")
        ocr.assert_called_once()

    def test_pdf_to_image_and_back(self):
        images = pdf_tools.pdf_to_images(self.pdf, self.out, "png", dpi=72)
        self.assertEqual(len(images), 3)
        self.assertTrue(os.path.getsize(images[0]) > 0)
        again = pdf_tools.images_to_pdf(images, os.path.join(self.out, "back.pdf"))
        self.assertEqual(pdf_tools.pdf_page_count(again), 3)

    def test_merge_and_split(self):
        other = make_pdf(self.tmp, "b.pdf", pages=2)
        merged = pdf_tools.merge_pdfs([self.pdf, other], os.path.join(self.out, "merged.pdf"))
        self.assertEqual(pdf_tools.pdf_page_count(merged), 5)
        archive = pdf_tools.split_pdf(merged, self.out, every=2)
        self.assertTrue(os.path.exists(archive))
        self.assertTrue(archive.endswith(".zip"))

    def test_engine_dispatch_pdf(self):
        out = engines.convert(self.pdf, "txt", self.out)
        self.assertTrue(out.endswith(".txt"))
        self.assertIn("hello page 2", open(out, encoding="utf-8").read())

    def test_html_escapes_extracted_text(self):
        path = os.path.join(self.tmp, "html.pdf")
        doc = canvas.Canvas(path)
        doc.drawString(72, 720, "A < B & C")
        doc.save()
        text = pdf_tools.pdf_to_html(path)
        self.assertIn("A &lt; B &amp; C", text)

    def test_pdf_table_extracts_text_as_text(self):
        from openpyxl import load_workbook
        path = os.path.join(self.tmp, "table.pdf")
        doc = canvas.Canvas(path)
        for x in (72, 200, 330): doc.line(x, 650, x, 730)
        for y in (650, 690, 730): doc.line(72, y, 330, y)
        doc.drawString(80, 705, "Name")
        doc.drawString(210, 705, "Amount")
        doc.drawString(80, 665, "Apple")
        doc.drawString(210, 665, "=1+2")
        doc.save()
        output = os.path.join(self.out, "tables.xlsx")
        pdf_tools.pdf_tables_to_xlsx(path, output)
        sheet = load_workbook(output, data_only=False).active
        self.assertEqual(sheet['A2'].value, 'Apple')
        self.assertEqual(sheet['B2'].value, '=1+2')
        self.assertEqual(sheet['B2'].data_type, 's')

    def test_image_export_zip_does_not_delete_existing_files(self):
        path = os.path.join(self.out, "a-01.png")
        with open(path, 'wb') as f: f.write(b'keep')
        archive = pdf_tools.pdf_to_images_zip(self.pdf, self.out, dpi=72)
        self.assertTrue(os.path.isfile(archive))
        with open(path, 'rb') as f: self.assertEqual(f.read(), b'keep')

    def test_zip(self):
        out = engines.zip_files([self.pdf], os.path.join(self.out, "pack.zip"))
        self.assertTrue(os.path.getsize(out) > 0)


if __name__ == "__main__":
    unittest.main()
