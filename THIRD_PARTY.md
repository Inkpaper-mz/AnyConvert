# Third-party components and references

AnyConvert's own source code is covered by the repository's MIT license. Third-party programs retain their own licenses; the MIT license does not replace them. Versions below describe the Apple Silicon test build prepared for this update, not all historical releases.

| Component | Purpose | Version / provenance | License and source |
| --- | --- | --- | --- |
| FFmpeg / ffprobe | Audio, video and image conversion | 9.0.2, static macOS arm64 build from [Martin Riedl](https://ffmpeg.martin-riedl.de/) | The build uses `--enable-gpl --enable-version3`; see [FFmpeg licensing](https://ffmpeg.org/legal.html), [FFmpeg source](https://github.com/FFmpeg/FFmpeg), and [build scripts](https://git.martin-riedl.de/ffmpeg/build-script). Exact corresponding sources for the distributed binary and its statically linked libraries must be verified and supplied before distributing a new binary. |
| LibreOffice | Office conversion | 26.8.2, The Document Foundation macOS distribution | [Licenses and third-party notices](https://www.libreoffice.org/licenses/); [source](https://git.libreoffice.org/core/). The application includes its own license notices. |
| Pandoc | Markdown and document conversion | 3.9, binary from `pypandoc_binary` 1.17 | [GPL-2.0-or-later and copyright notices](https://github.com/jgm/pandoc/blob/3.9/COPYRIGHT); [3.9 source](https://github.com/jgm/pandoc/tree/3.9). Invoked as a separate program. |
| libvips and librsvg | SVG rasterization | libvips 8.18.7; `@img/sharp-libvips-darwin-arm64` 1.3.4 | The build is LGPL-3.0-or-later with third-party components; see the package [notices](https://github.com/lovell/sharp-libvips/blob/main/THIRD-PARTY-NOTICES.md), [build repository](https://github.com/lovell/sharp-libvips), [libvips](https://github.com/libvips/libvips), and [librsvg](https://gitlab.gnome.org/GNOME/librsvg). Versions and notices are included in the application. |
| LibRaw | Camera RAW decoding | 0.22.2, conda-forge build `h2d05ff4_0`, with dynamic-library paths adjusted for the application | [LGPL-2.1](https://github.com/LibRaw/LibRaw/blob/master/LICENSE.LGPL); [source](https://github.com/LibRaw/LibRaw/tree/0.22.2); [build recipe](https://github.com/conda-forge/libraw-feedstock). |
| PDFium / pypdfium2 | PDF rasterization and text in Python cross-platform source | Python dependency; Python distributions are paused | [pypdfium2 license information](https://github.com/pypdfium2-team/pypdfium2#licensing): Apache-2.0 OR BSD-3-Clause; PDFium and bundled dependencies have separate notices. Verify each binary build before distribution. |
| pypdf | PDF page merge and split in Python source | Python dependency; Python distributions are paused | [BSD-3-Clause](https://github.com/py-pdf/pypdf/blob/main/LICENSE). |
| pdfplumber / pdfminer.six | Table extraction in Python source | Python dependency; Python distributions are paused | [pdfplumber MIT](https://github.com/jsvine/pdfplumber/blob/stable/LICENSE.txt); [pdfminer.six MIT](https://github.com/pdfminer/pdfminer.six/blob/master/LICENSE). |
| Pillow | Image-to-PDF and bitmap conversion in Python source | Python dependency; Python distributions are paused | [Pillow license and third-party notices](https://github.com/python-pillow/Pillow/blob/main/LICENSE). |
| PDFKit, Vision and ImageIO | PDF and OCR | macOS system frameworks | Apple platform components, not bundled third-party open-source libraries. |

## Product references

File Converter and FlyingMouse Format were considered as feature references. No source code from either project was copied into this update. [File Converter](https://github.com/Tichau/FileConverter) is a separate project with its own license. FlyingMouse Format's source and license have not been independently established for this release; no rights to its code are asserted here.

The macOS test builds use ad-hoc signing and have not been notarized. Before publishing downloadable binaries, verify the exact corresponding source, notices and redistribution obligations for every bundled component and the ability to replace LGPL libraries.

## Distribution review: unresolved items

- Current Python source no longer directly imports PyMuPDF or pdf2docx; historic releases and history have not been rewritten or audited, and may contain different dependencies. Python distributions are paused and no new Windows or Linux installer has been produced or verified.
- PDFium binary wheels include additional third-party dependencies; verify the exact bundled license notices and versions before distributing a Python package. PDF-to-HTML now exports escaped plain text, not layout-preserving HTML, and table extraction uses a different algorithm.
- Separate executables do not by themselves establish a definitive legal conclusion about aggregation. Distribution obligations depend on the complete combination, applicable versions and actual licensing terms; seek qualified advice where needed.
- The 9.0.2 FFmpeg build is configured with GPL and version 3 enabled and includes x264/x265; providing a license text and an arbitrary source link alone has not been verified as sufficient for this specific binary. Obtain exact corresponding source, third-party source and the build scripts/configuration or use a reproducible build before distributing.
- LibreOffice includes components with distinct terms; retain its bundled license and third-party notices and verify obligations for any modified files and bundled build.
