import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from crossplatform.core import engines
from crossplatform.core.compress import (
    TargetUnreachable, compress_image_to_target, compress_video_to_target,
)
from crossplatform.core.queue import ConversionQueue


def ffmpeg():
    return engines.find_ffmpeg()


def make_image(directory, width=640, height=480):
    out = os.path.join(directory, "big.jpg")
    subprocess.run([ffmpeg(), "-hide_banner", "-loglevel", "error", "-y",
                    "-f", "lavfi", "-i", f"testsrc2=size={width}x{height}:rate=1",
                    "-frames:v", "1", "-q:v", "2", out], check=True)
    return out


def make_video(directory, seconds=1, size="320x240"):
    out = os.path.join(directory, "big.mp4")
    subprocess.run([ffmpeg(), "-hide_banner", "-loglevel", "error", "-y",
                    "-f", "lavfi", "-i", f"testsrc2=size={size}:rate=25:duration={seconds}",
                    "-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}",
                    "-c:v", "libx264", "-crf", "18", "-c:a", "aac", "-shortest", out], check=True)
    return out


class ImageCompressionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.out = tempfile.mkdtemp()

    def test_image_hits_target(self):
        src = make_image(self.tmp)
        target = 20 * 1024
        self.assertGreater(os.path.getsize(src), target)
        result = compress_image_to_target(src, target, self.out)
        self.assertTrue(os.path.exists(result))
        self.assertLessEqual(os.path.getsize(result), target * 1.02)

    def test_image_unreachable_reports_best(self):
        src = make_image(self.tmp, 320, 240)
        with self.assertRaises(TargetUnreachable) as context:
            compress_image_to_target(src, 200, self.out)
        self.assertIn("无法压缩到", str(context.exception))
        self.assertGreater(context.exception.best_bytes, 200)


class VideoCompressionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.out = tempfile.mkdtemp()

    def test_video_hits_target(self):
        src = make_video(self.tmp)
        target = 40 * 1024
        self.assertGreater(os.path.getsize(src), target)
        result = compress_video_to_target(src, target, self.out)
        self.assertTrue(os.path.exists(result))
        self.assertLessEqual(os.path.getsize(result), target * 1.02)

    def test_queue_with_target_size(self):
        src = make_video(self.tmp)
        queue = ConversionQueue(max_workers=3)
        accepted, rejected = queue.add([src], "mp4", target_bytes=30 * 1024)
        self.assertEqual(len(accepted), 1)
        queue.start()
        import time
        deadline = time.time() + 30
        while time.time() < deadline and queue.stats()["done"] + queue.stats()["failed"] == 0:
            time.sleep(0.1)
        job = queue.snapshot()[0]
        self.assertEqual(job["status"], "done", job["error"])
        self.assertLessEqual(os.path.getsize(job["output"]), 30 * 1024 * 1.02)


if __name__ == "__main__":
    unittest.main()
