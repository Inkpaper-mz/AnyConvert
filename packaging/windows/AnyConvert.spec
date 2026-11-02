# -*- mode: python ; coding: utf-8 -*-
import os

ROOT = os.path.abspath(os.path.join(SPECPATH, "..", ".."))

a = Analysis(
    [os.path.join(ROOT, 'run_web.py')],
    pathex=[ROOT],
    binaries=[
        (os.path.join(ROOT,'vendor/win/ffmpeg.exe'), 'vendor/win'),
        (os.path.join(ROOT,'vendor/win/ffprobe.exe'), 'vendor/win'),
    ],
    datas=[
        (os.path.join(ROOT,'crossplatform/core/matrix.json'), 'crossplatform/core'),
        (os.path.join(ROOT,'webui/static'), 'webui/static'),
        (os.path.join(ROOT,'docs'), 'docs'),
        (os.path.join(ROOT,'README.md'), '.'),
        (os.path.join(ROOT,'START-HERE.txt'), '.'),
    ],
    hiddenimports=['fitz', 'openpyxl', 'PIL'],
    hookspath=[],
    runtime_hooks=[],
    excludes=['tkinter', 'matplotlib', 'pytest'],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz, a.scripts, [],
    exclude_binaries=True,
    name='AnyConvert',
    debug=False,
    strip=False,
    upx=False,
    console=True,
)
coll = COLLECT(
    exe, a.binaries, a.datas,
    strip=False,
    upx=False,
    name='AnyConvert',
)
