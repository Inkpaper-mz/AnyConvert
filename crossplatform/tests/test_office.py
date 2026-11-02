import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from crossplatform.core import engines


def has_soffice() -> bool:
    try:
        engines.find_soffice()
        return True
    except Exception:  # noqa: BLE001
        return False


class OfficeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()

    @unittest.skipUnless(has_soffice(), "LibreOffice not bundled")
    def test_txt_to_pdf_through_libreoffice(self):
        source = os.path.join(self.tmp, "note.txt")
        open(source, "w", encoding="utf-8").write("标题\n万能转码测试文档。\n")
        output = engines.convert(source, "pdf", self.tmp)
        self.assertTrue(output.endswith(".pdf"))
        with open(output, "rb") as handle:
            self.assertEqual(handle.read(5), b"%PDF-")

    @unittest.skipUnless(has_soffice(), "LibreOffice not bundled")
    def test_xlsx_to_pdf(self):
        from openpyxl import Workbook
        path = os.path.join(self.tmp, "sheet.xlsx")
        workbook = Workbook()
        sheet = workbook.active
        sheet["A1"] = "名称"
        sheet["B1"] = "数量"
        sheet["A2"] = "苹果"
        sheet["B2"] = 12
        workbook.save(path)
        output = engines.convert(path, "pdf", self.tmp)
        with open(output, "rb") as handle:
            self.assertEqual(handle.read(5), b"%PDF-")

    def test_ocr_vision(self):
        from crossplatform.core import ocr
        image = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
            os.path.abspath(__file__)))), "docs", "qt-tools.png")
        if not os.path.exists(image):
            self.skipTest("screenshot missing")
        text = ocr.ocr_image(image)
        self.assertIn("万能转码", text)

    def test_engine_status_includes_ocr(self):
        status = engines.engine_status()
        self.assertIn("ocr", status)
        self.assertTrue(status["libreoffice"]["available"] or not has_soffice())


if __name__ == "__main__":
    unittest.main()
