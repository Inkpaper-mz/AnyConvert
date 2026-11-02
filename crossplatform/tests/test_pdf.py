import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

try:
    import fitz
except Exception:  # noqa: BLE001
    fitz = None

from crossplatform.core import engines, pdf_tools


def make_pdf(directory, name="a.pdf", pages=2):
    doc = fitz.open()
    for index in range(pages):
        page = doc.new_page()
        page.insert_text((72, 72), f"hello page {index + 1}")
    path = os.path.join(directory, name)
    doc.save(path)
    doc.close()
    return path


@unittest.skipIf(fitz is None, "PyMuPDF not installed")
class PdfTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.out = tempfile.mkdtemp()
        self.pdf = make_pdf(self.tmp, pages=3)

    def test_pdf_to_text(self):
        text = pdf_tools.pdf_to_text(self.pdf)
        self.assertIn("hello page 1", text)
        self.assertEqual(pdf_tools.pdf_page_count(self.pdf), 3)

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

    def test_zip(self):
        out = engines.zip_files([self.pdf], os.path.join(self.out, "pack.zip"))
        self.assertTrue(os.path.getsize(out) > 0)


if __name__ == "__main__":
    unittest.main()
