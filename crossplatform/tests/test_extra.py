import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

try:
    import fitz
except Exception:  # noqa: BLE001
    fitz = None

from crossplatform.core import engines, pdf_tools


class ExtraTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()

    def test_image_to_video(self):
        ffmpeg = engines.find_ffmpeg()
        image = os.path.join(self.tmp, "frame.png")
        subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                        "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=1",
                        "-frames:v", "1", image], check=True)
        output = engines.convert(image, "mp4", self.tmp)
        probe = subprocess.run([engines.find_ffprobe(), "-v", "error", "-show_entries",
                                "format=duration", "-of", "csv=p=0", output],
                               capture_output=True).stdout.decode().strip()
        self.assertGreater(float(probe), 1.0)

    def test_zip_level(self):
        path = os.path.join(self.tmp, "a.txt")
        open(path, "w").write("hello" * 100)
        out = engines.zip_files([path], os.path.join(self.tmp, "a.zip"), 9)
        self.assertGreater(os.path.getsize(out), 0)

    @unittest.skipIf(fitz is None, "PyMuPDF not installed")
    def test_pdf_images_zip(self):
        doc = fitz.open()
        for _ in range(2):
            doc.new_page().insert_text((72, 72), "hello")
        pdf = os.path.join(self.tmp, "a.pdf")
        doc.save(pdf)
        doc.close()
        out = pdf_tools.pdf_to_images_zip(pdf, self.tmp)
        import zipfile
        with zipfile.ZipFile(out) as zf:
            self.assertEqual(len(zf.namelist()), 2)

    def test_cli_capabilities(self):
        result = subprocess.run([sys.executable, "-m", "crossplatform.cli", "capabilities", "--json"],
                                capture_output=True, cwd=os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
        data = json.loads(result.stdout)
        self.assertIn("targets", data)
        self.assertGreater(len(data["targets"]), 40)


if __name__ == "__main__":
    unittest.main()
