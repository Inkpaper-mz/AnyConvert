# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['run_web.py'],
    pathex=[],
    binaries=[('"vendor/win/ffmpeg.exe', 'vendor/win"'), ('"vendor/win/ffprobe.exe', 'vendor/win"')],
    datas=[('"crossplatform', 'crossplatform"'), ('"webui', 'webui"'), ('"docs', 'docs"')],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='AnyConvert',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='AnyConvert',
)
