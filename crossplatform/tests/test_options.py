import os
import subprocess
import sys
import tempfile
import threading
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from crossplatform.core import engines
from crossplatform.core.queue import ConversionQueue


def make_video(directory):
    out = os.path.join(directory, "src.mp4")
    subprocess.run([engines.find_ffmpeg(), "-hide_banner", "-loglevel", "error", "-y",
                    "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=25:duration=2",
                    "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
                    "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac", "-shortest", out],
                   check=True)
    return out


def probe(path, entries):
    out = subprocess.run([engines.find_ffprobe(), "-v", "error", "-select_streams", "v:0",
                          "-show_entries", entries, "-of", "csv=p=0", path],
                         capture_output=True).stdout.decode().strip()
    return out


class OptionsTests(unittest.TestCase):
    def test_resolution_fps_are_applied(self):
        tmp = tempfile.mkdtemp()
        src = make_video(tmp)
        queue = ConversionQueue(max_workers=1)
        options = {"resolution": "custom", "width": 320, "height": 240,
                   "quality": "small", "fps": 30, "audio_kbps": 128, "codec": "h264"}
        accepted, rejected = queue.add([src], "mp4", None, "h264", options)
        self.assertEqual(len(accepted), 1, rejected)
        queue.start()
        deadline = __import__("time").time() + 30
        while __import__("time").time() < deadline and queue.stats()["done"] + queue.stats()["failed"] == 0:
            __import__("time").sleep(0.1)
        job = queue.snapshot()[0]
        self.assertEqual(job["status"], "done", job["error"])
        info = probe(job["output"], "stream=width,height,r_frame_rate")
        width, height, rate = info.split(",")[:3]
        self.assertEqual((int(width), int(height)), (320, 240))
        num, den = rate.split("/")
        self.assertAlmostEqual(float(num) / float(den), 30.0, delta=0.5)


if __name__ == "__main__":
    unittest.main()
