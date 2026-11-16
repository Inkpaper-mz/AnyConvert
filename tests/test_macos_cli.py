"""Integration checks for the native macOS CLI; run after `swift build`."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / '.build/debug/AnyConvert'
LO = ROOT / 'crossplatform/vendor/LibreOffice.app/Contents/MacOS/soffice'

@unittest.skipUnless(BIN.exists() and LO.exists(), 'Build app and install LibreOffice fixture first')
class NativeCLI(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        source = self.dir / 'fixture.txt'
        source.write_text('Document conversion regression test', encoding='utf-8')
        subprocess.run([str(LO), '-env:UserInstallation=' + (self.dir / 'profile').as_uri(),
                        '--headless', '--convert-to', 'docx', '--outdir', str(self.dir), str(source)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.source = self.dir / 'fixture.docx'
        self.assertTrue(self.source.is_file())

    def tearDown(self):
        self.tmp.cleanup()

    def call(self, *args):
        env = dict(os.environ, SOFFICE=str(LO))
        return subprocess.run([str(BIN), '--cli', *map(str, args), '--json'],
                              env=env, capture_output=True, text=True, timeout=90)

    def test_docx_targets_use_document_matrix_for_file_and_extension(self):
        for value in ('docx', self.source):
            result = self.call('--targets', value)
            self.assertEqual(result.returncode, 0, result.stderr)
            formats = {item['id'] for item in json.loads(result.stdout)['targets']}
            self.assertIn('pdf', formats)
            self.assertNotIn('mp4', formats)
            self.assertNotIn('mp3', formats)

    def test_docx_to_pdf(self):
        result = self.call('-i', self.source, '--to', 'pdf', '-o', self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertTrue(data['ok'])
        self.assertTrue(Path(data['output']).read_bytes().startswith(b'%PDF-'))

    def test_unsupported_document_conversion_does_not_create_output(self):
        result = self.call('-i', self.source, '--to', 'mp3', '-o', self.dir)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stderr)['errorCode'], 'E_TARGET')
        self.assertFalse((self.dir / 'fixture.mp3').exists())

    def test_still_image_converts_to_finite_video(self):
        ffmpeg = ROOT / 'vendor/ffmpeg'
        ffprobe = ROOT / 'vendor/ffprobe'
        if not ffmpeg.exists() or not ffprobe.exists():
            self.skipTest('FFmpeg is not installed')
        image = self.dir / 'still.png'
        subprocess.run([str(ffmpeg), '-loglevel', 'error', '-y', '-f', 'lavfi', '-i',
                        'color=c=blue:s=128x128', '-frames:v', '1', '-update', '1', str(image)], check=True)
        for target in ('mp4', 'webm'):
            result = self.call('-i', image, '--to', target, '-o', self.dir)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = json.loads(result.stdout)['output']
            probe = subprocess.run([str(ffprobe), '-v', 'error', '-show_entries',
                                    'format=duration', '-of', 'default=nw=1:nk=1', output],
                                   capture_output=True, text=True, check=True)
            self.assertGreater(float(probe.stdout), 4.5)
            self.assertLess(float(probe.stdout), 5.5)

    def test_video_codecs_match_requested_format(self):
        ffmpeg, ffprobe = ROOT / 'vendor/ffmpeg', ROOT / 'vendor/ffprobe'
        if not ffmpeg.exists() or not ffprobe.exists():
            self.skipTest('FFmpeg is not installed')
        source = self.dir / 'video.mp4'
        subprocess.run([str(ffmpeg), '-loglevel', 'error', '-y', '-f', 'lavfi', '-i',
                        'testsrc2=size=128x128:rate=10:duration=1', '-c:v', 'libx264', str(source)], check=True)
        for codec, expected in (('h264', 'h264'), ('h265', 'hevc'), ('av1', 'av1')):
            result = self.call('-i', source, '--to', 'mp4', '--codec', codec, '-o', self.dir)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = json.loads(result.stdout)['output']
            probe = subprocess.run([str(ffprobe), '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                                    'stream=codec_name', '-of', 'default=nw=1:nk=1', output],
                                   capture_output=True, text=True, check=True)
            self.assertEqual(probe.stdout.strip(), expected)

    def test_markdown_word_roundtrip(self):
        if not (ROOT / 'vendor/pandoc/pandoc').exists():
            self.skipTest('Pandoc is not installed')
        source = self.dir / 'sample.md'
        source.write_text('# Heading Alpha\n\n| Name | Value |\n|---|---|\n| Apple | 42 |\n\n```\nlet x = 1\n```\n', encoding='utf-8')
        result = self.call('-i', source, '--to', 'docx', '-o', self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.call('-i', json.loads(result.stdout)['output'], '--to', 'md', '-o', self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = Path(json.loads(result.stdout)['output']).read_text(encoding='utf-8')
        for expected in ('Heading Alpha', 'Name', 'Value', 'Apple', '42', 'let x = 1'):
            self.assertIn(expected, text)

    def test_csv_json_roundtrip_with_quotes_and_newlines(self):
        import csv
        source = self.dir / 'records.csv'
        original = [['姓名', '备注'], ['小王', '逗号, 双引号" 和\n换行'], ['小李', '00042']]
        with source.open('w', encoding='utf-8', newline='') as f:
            csv.writer(f).writerows(original)
        result = self.call('-i', source, '--to', 'json', '-o', self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        json_path = Path(json.loads(result.stdout)['output'])
        objects = json.loads(json_path.read_text())
        self.assertEqual(objects[0]['备注'], original[1][1])
        self.assertEqual(objects[1]['备注'], '00042')
        result = self.call('-i', json_path, '--to', 'csv', '-o', self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        with Path(json.loads(result.stdout)['output']).open(encoding='utf-8', newline='') as f:
            records = list(csv.DictReader(f))
        self.assertEqual(records, objects)

    def test_json_nested_data_rejected(self):
        source = self.dir / 'nested.json'
        source.write_text('[{"item": {"nested": 1}}]', encoding='utf-8')
        result = self.call('-i', source, '--to', 'csv', '-o', self.dir)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stderr)['errorCode'], 'E_CONVERT')

    def test_pdf_to_markdown_extracts_text(self):
        result = self.call('-i', self.source, '--to', 'pdf', '-o', self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        pdf = json.loads(result.stdout)['output']
        result = self.call('-i', pdf, '--to', 'md', '-o', self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = Path(json.loads(result.stdout)['output']).read_text(encoding='utf-8')
        self.assertIn('Document conversion regression test', text)

    def test_csv_and_json_render_to_documents(self):
        if not (ROOT / 'vendor/pandoc/pandoc').exists(): self.skipTest('Pandoc is not installed')
        csv_path = self.dir / 'table.csv'
        csv_path.write_text('name,value\nApple,42\n', encoding='utf-8')
        json_path = self.dir / 'table.json'
        json_path.write_text('[{"name":"Apple","value":"42"}]', encoding='utf-8')
        for source in (csv_path, json_path):
            for target in ('md', 'html', 'docx', 'pdf'):
                result = self.call('-i', source, '--to', target, '-o', self.dir)
                self.assertEqual(result.returncode, 0, result.stderr)
                output = Path(json.loads(result.stdout)['output'])
                self.assertGreater(output.stat().st_size, 0)
                if target in ('md', 'html'):
                    text = output.read_text(encoding='utf-8')
                    self.assertIn('Apple', text)
                    self.assertIn('42', text)

    def test_txt_json_roundtrip_preserves_literal_text(self):
        source = self.dir / 'literal.txt'
        expected = '中文, quote " and\n**literal**\n'
        source.write_text(expected, encoding='utf-8')
        result = self.call('-i', source, '--to', 'json', '-o', self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.call('-i', json.loads(result.stdout)['output'], '--to', 'txt', '-o', self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(json.loads(result.stdout)['output']).read_text(encoding='utf-8'), expected)

    def test_scanned_pdf_to_markdown_uses_ocr(self):
        try:
            import fitz
        except ImportError:
            self.skipTest('PyMuPDF is required to create the scan fixture')
        raster_source = fitz.open()
        page = raster_source.new_page(width=600, height=300)
        page.insert_text((50, 120), 'SCANNED DOCUMENT ALPHA', fontsize=32)
        pix = page.get_pixmap(matrix=fitz.Matrix(2, 2), alpha=False)
        pdf = fitz.open()
        p = pdf.new_page(width=600, height=300)
        p.insert_image(p.rect, stream=pix.tobytes('png'))
        path = self.dir / 'scan.pdf'
        pdf.save(str(path))
        pdf.close()
        raster_source.close()
        result = self.call('-i', path, '--to', 'md', '-o', self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        result_text = Path(json.loads(result.stdout)['output']).read_text(encoding='utf-8')
        self.assertIn('SCANNED', result_text.upper())
        self.assertIn('ALPHA', result_text.upper())

    def test_malformed_csv_fails_without_output(self):
        source = self.dir / 'broken.csv'
        source.write_text('name,value\n"unterminated,42\n', encoding='utf-8')
        result = self.call('-i', source, '--to', 'json', '-o', self.dir)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stderr)['errorCode'], 'E_CONVERT')
        self.assertFalse((self.dir / 'broken.json').exists())

    def test_csv_duplicate_headers_are_rejected(self):
        source = self.dir / 'duplicate.csv'
        source.write_text('name,name\nfirst,second\n', encoding='utf-8')
        result = self.call('-i', source, '--to', 'json', '-o', self.dir)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.dir / 'duplicate.json').exists())

    def test_markdown_and_html_table_to_csv_and_json(self):
        if not (ROOT / 'vendor/pandoc/pandoc').exists(): self.skipTest('Pandoc is not installed')
        for name, content in [('table.md', '| name | value |\n|---|---|\n| Apple | 42 |\n'),
                              ('table.html', '<table><thead><tr><th>name</th><th>value</th></tr></thead><tbody><tr><td>Apple</td><td>42</td></tr></tbody></table>')]:
            source = self.dir / name
            source.write_text(content, encoding='utf-8')
            for target in ('csv', 'json'):
                result = self.call('-i', source, '--to', target, '-o', self.dir)
                self.assertEqual(result.returncode, 0, result.stderr)
                text = Path(json.loads(result.stdout)['output']).read_text(encoding='utf-8')
                self.assertIn('Apple', text)
                self.assertIn('42', text)

    def test_markdown_with_body_rejected_as_csv(self):
        source = self.dir / 'body.md'
        source.write_text('Keep this paragraph\n\n| name | value |\n|---|---|\n| A | 1 |\n', encoding='utf-8')
        result = self.call('-i', source, '--to', 'csv', '-o', self.dir)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.dir / 'body.csv').exists())

    def test_table_links_rejected_as_csv(self):
        source = self.dir / 'link.md'
        source.write_text('| name | value |\n|---|---|\n| [A](https://example.com) | 1 |\n', encoding='utf-8')
        result = self.call('-i', source, '--to', 'csv', '-o', self.dir)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.dir / 'link.csv').exists())

    def test_html_to_docx_preserves_text_and_table(self):
        import zipfile
        if not (ROOT / 'vendor/pandoc/pandoc').exists(): self.skipTest('Pandoc is not installed')
        source = self.dir / 'lesson.html'
        source.write_text('<!doctype html><html><meta charset="utf-8"><h1>中文标题</h1><p>课程内容</p><table><tr><th>单元</th><th>权重</th></tr><tr><td>循环</td><td>25%</td></tr></table></html>', encoding='utf-8')
        result = self.call('-i', source, '--to', 'docx', '-o', self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(json.loads(result.stdout)['output']) as z:
            xml = z.read('word/document.xml').decode('utf-8')
        for value in ('中文标题', '课程内容', '循环', '25%'):
            self.assertIn(value, xml)
        self.assertIn('<w:tbl>', xml)

    def test_psd_and_exr_are_recognized_as_images(self):
        import struct
        ffmpeg = ROOT / 'vendor/ffmpeg'
        if not ffmpeg.exists(): self.skipTest('FFmpeg is not installed')
        psd = self.dir / 'sample.psd'
        psd.write_bytes(b'8BPS' + struct.pack('>H', 1) + b'\0' * 6 +
                        struct.pack('>HIIHH', 3, 2, 2, 8, 3) + struct.pack('>IIIH', 0, 0, 0, 0) +
                        bytes([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255]))
        exr = self.dir / 'sample.exr'
        subprocess.run([str(ffmpeg), '-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi',
                        '-i', 'color=blue:s=128x128', '-frames:v', '1', str(exr)], check=True)
        for source in (psd, exr):
            result = self.call('--targets', source)
            self.assertEqual(result.returncode, 0, result.stderr)
            targets = {item['id'] for item in json.loads(result.stdout)['targets']}
            self.assertIn('png', targets)
            self.assertNotIn('mp3', targets)
            result = self.call('-i', source, '--to', 'png', '-o', self.dir)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = json.loads(result.stdout)['output']
            probe = subprocess.run([str(ffmpeg), '-v', 'error', '-i', output, '-frames:v', '1',
                                    '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], capture_output=True, check=True)
            self.assertTrue(any(probe.stdout))

    def test_svg_raster_conversion_and_invalid_input(self):
        ffmpeg = ROOT / 'vendor/ffmpeg'
        helper = ROOT / 'vendor/libvips/vips-helper'
        if not ffmpeg.exists() or not helper.exists(): self.skipTest('SVG engine not installed')
        source = self.dir / 'vector.svg'
        source.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="32"><rect width="64" height="32" fill="#ff0000"/></svg>', encoding='utf-8')
        for target in ('png', 'webp', 'pdf'):
            result = self.call('-i', source, '--to', target, '-o', self.dir)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = Path(json.loads(result.stdout)['output'])
            self.assertGreater(output.stat().st_size, 0)
            if target == 'png':
                image = subprocess.run([str(ffmpeg), '-v', 'error', '-i', str(output), '-frames:v', '1',
                                        '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], capture_output=True, check=True).stdout
                self.assertEqual(len(image), 64 * 32 * 3)
                self.assertGreater(image[0], 240)
                self.assertLess(image[1], 15)
        source.write_text('<svg><broken', encoding='utf-8')
        result = self.call('-i', source, '--to', 'png', '-o', self.dir)
        self.assertNotEqual(result.returncode, 0)

    def test_svg_oversized_rejected(self):
        if not (ROOT / 'vendor/libvips/vips-helper').exists(): self.skipTest('SVG engine not installed')
        source = self.dir / 'huge.svg'
        source.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="20000" height="20000"><rect width="10" height="10"/></svg>', encoding='utf-8')
        result = self.call('-i', source, '--to', 'png', '-o', self.dir)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.dir / 'huge.png').exists())

    def test_invalid_raw_rejected(self):
        if not (ROOT / 'vendor/libraw/dcraw_emu').exists(): self.skipTest('LibRaw is not installed')
        source = self.dir / 'invalid.nef'
        source.write_bytes(b'not a raw image')
        result = self.call('-i', source, '--to', 'png', '-o', self.dir)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.dir / 'invalid.png').exists())

    def test_real_raw_fixture_if_available(self):
        fixture = os.environ.get('ANYCONVERT_RAW_FIXTURE')
        if not fixture: self.skipTest('Set ANYCONVERT_RAW_FIXTURE to a licensed RAW sample')
        result = self.call('-i', fixture, '--to', 'png', '-o', self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = Path(json.loads(result.stdout)['output'])
        self.assertTrue(output.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'))
        self.assertGreater(output.stat().st_size, 1000)

    def test_image_targets_include_ocr_and_pdf(self):
        result = self.call('--targets', 'png')
        formats = {item['id'] for item in json.loads(result.stdout)['targets']}
        self.assertTrue({'pdf', 'txt', 'jpg'}.issubset(formats))

if __name__ == '__main__':
    unittest.main()
