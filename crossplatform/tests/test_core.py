import os
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from crossplatform.core import engines
from crossplatform.core.matrix import MATRIX, normalize_ext
from crossplatform.core.queue import ConversionQueue


def make_file(directory, name, size=8):
    path = os.path.join(directory, name)
    with open(path, "wb") as handle:
        handle.write(b"0" * size)
    return path


class MatrixTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()

    def test_pdf_accepts_docx_and_png(self):
        for name in ("a.docx", "b.png"):
            path = make_file(self.tmp, name)
            self.assertTrue(MATRIX.validate("pdf", path).ok, name)

    def test_docx_rejects_jpg_with_exact_message(self):
        path = make_file(self.tmp, "photo.jpg")
        result = MATRIX.validate("docx", path)
        self.assertFalse(result.ok)
        self.assertEqual(result.reason, "不支持将 .jpg 转换为 .docx，请检查文件类型。")

    def test_unknown_target(self):
        path = make_file(self.tmp, "a.txt")
        self.assertFalse(MATRIX.validate("xyz", path).ok)

    def test_alias_normalization(self):
        self.assertEqual(normalize_ext("JPEG"), "jpg")
        self.assertEqual(normalize_ext(".jpeg"), "jpg")

    def test_engine_choice(self):
        png = make_file(self.tmp, "a.png")
        mp4 = make_file(self.tmp, "a.mp4")
        self.assertEqual(MATRIX.choose_engine("pdf", png), "pymupdf")
        self.assertEqual(MATRIX.choose_engine("png", png), "ffmpeg")
        self.assertEqual(MATRIX.choose_engine("mp3", mp4), "ffmpeg")
        docx = make_file(self.tmp, "a.docx")
        self.assertEqual(MATRIX.choose_engine("pdf", docx), "libreoffice")


class QueueTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()

    def test_rejected_files_never_enter_queue(self):
        good = make_file(self.tmp, "a.mp4")
        bad = make_file(self.tmp, "b.jpg")
        queue = ConversionQueue(max_workers=3)
        accepted, rejected = queue.add([good, bad], "mp3")
        self.assertEqual([j.src for j in accepted], [good])
        self.assertEqual(len(rejected), 1)
        self.assertEqual(len(queue.jobs), 1)

    def test_max_concurrency_is_three(self):
        paths = [make_file(self.tmp, f"{i}.mp4") for i in range(8)]
        queue = ConversionQueue(max_workers=3)
        queue.add(paths, "mp3")

        lock = threading.Lock()
        active = {"now": 0, "peak": 0}
        original = engines.convert

        def fake_convert(src, target, out_dir, progress=None, cancel=None, target_bytes=None,
                         codec="h264", options=None):
            with lock:
                active["now"] += 1
                active["peak"] = max(active["peak"], active["now"])
            time.sleep(0.15)
            with lock:
                active["now"] -= 1
            return src + ".out"

        engines.convert = fake_convert
        try:
            queue.start()
            deadline = time.time() + 10
            while time.time() < deadline:
                if queue.stats()["done"] == len(paths):
                    break
                time.sleep(0.05)
        finally:
            engines.convert = original

        self.assertLessEqual(active["peak"], 3)
        self.assertGreaterEqual(active["peak"], 2)


class EngineTests(unittest.TestCase):
    def test_ffmpeg_available(self):
        try:
            path = engines.find_ffmpeg()
        except engines.EngineUnavailable:
            self.skipTest("ffmpeg not installed")
        self.assertTrue(os.path.isfile(path))

    def test_libreoffice_missing_is_graceful(self):
        try:
            engines.find_soffice()
        except engines.EngineUnavailable as exc:
            self.assertIn("LibreOffice", str(exc))
        else:
            self.skipTest("LibreOffice installed")


if __name__ == "__main__":
    unittest.main()
