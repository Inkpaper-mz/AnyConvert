#!/usr/bin/env python3
"""安装/卸载系统右键菜单（Finder 服务 / Windows 资源管理器 / Nautilus）。

用法：
    python3 scripts/install_context_menu.py install
    python3 scripts/install_context_menu.py install --formats mp4,mp3,pdf,jpg,png
    python3 scripts/install_context_menu.py uninstall
"""

from __future__ import annotations

import argparse
import os
import platform
import plistlib
import shutil
import subprocess
import sys
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PYTHON = sys.executable or "/usr/bin/python3"
CLI = f'"{PYTHON}" -m crossplatform.cli'
FORMATS = {
    "mp4": "MP4 视频",
    "mp3": "MP3 音频",
    "pdf": "PDF",
    "jpg": "JPG 图片",
    "png": "PNG 图片",
    "gif": "GIF 动图",
}
SERVICE_PREFIX = "万能转码 · 转 "


def script_for(target: str) -> str:
    log = os.path.join(ROOT, "service.log")
    return f'''#!/bin/bash
{{
  echo "[$(date)] args=$* python="{PYTHON}""
  cd "{ROOT}" || echo "cd failed: {ROOT}"
}} >>"{log}" 2>&1
for f in "$@"; do
  "{PYTHON}" -m crossplatform.cli convert -i "$f" --to {target} >>"{log}" 2>&1
  if [ $? -eq 0 ]; then
    /usr/bin/osascript -e 'display notification "'"$(basename "$f")"' → {target.upper()}" with title "万能转码"'
  else
    /usr/bin/osascript -e 'display notification "转换失败，查看 service.log" with title "万能转码"'
  fi
done
'''


# ---------------------------------------------------------------- macOS

def mac_service_dir(name: str) -> str:
    return os.path.expanduser(f"~/Library/Services/{name}.workflow")


def install_macos(formats: list[str]) -> None:
    for target in formats:
        name = f"{SERVICE_PREFIX}{target.upper()}"
        bundle = mac_service_dir(name)
        contents = os.path.join(bundle, "Contents")
        os.makedirs(contents, exist_ok=True)

        info = {
            "CFBundleIdentifier": f"com.anyconvert.service.{target}",
            "CFBundleName": name,
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": "1.0",
            "NSServices": [{
                "NSMenuItem": {"default": name},
                "NSMessage": "runWorkflowAsService",
                "NSRequiredContext": {"NSApplicationIdentifier": "com.apple.finder"},
                "NSSendFileTypes": ["public.item"],
            }],
        }
        with open(os.path.join(contents, "Info.plist"), "wb") as handle:
            plistlib.dump(info, handle)

        uuids = [str(uuid.uuid4()).upper() for _ in range(3)]
        workflow = {
            "AMApplicationBuild": "523",
            "AMApplicationVersion": "2.10",
            "AMDocumentVersion": "2",
            "actions": [{
                "action": {
                    "AMAccepts": {"Container": "com.apple.cocoa.string", "Optional": True,
                                  "Types": ["com.apple.cocoa.string"]},
                    "AMActionVersion": "2.0.3",
                    "AMApplication": ["Automator"],
                    "AMParameterProperties": {},
                    "AMProvides": {"Container": "com.apple.cocoa.string",
                                   "Types": ["com.apple.cocoa.string"]},
                    "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
                    "ActionName": "Run Shell Script",
                    "ActionParameters": {
                        "COMMAND_STRING": script_for(target),
                        "CheckedForUserDefaultShell": True,
                        "inputMethod": 1,
                        "shell": "/bin/bash",
                        "source": "",
                    },
                    "BundleIdentifier": "com.apple.RunShellScript",
                    "CFBundleVersion": "2.0.3",
                    "CanShowSelectedItemsWhenRun": False,
                    "CanShowWhenRun": True,
                    "Category": ["AMCategoryUtilities"],
                    "Class Name": "RunShellScriptAction",
                    "InputUUID": uuids[0],
                    "Keywords": ["Shell", "Script", "Convert"],
                    "OutputUUID": uuids[1],
                    "UUID": uuids[2],
                    "UnlocalizedApplications": ["Automator"],
                    "arguments": {},
                    "isViewVisible": 1,
                    "location": "309.000000:253.000000",
                    "nibPath": "/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib",
                },
                "isViewVisible": 1,
            }],
            "connectors": {},
            "workflowMetaData": {
                "applicationBundleIDsByPath": {},
                "applicationPaths": [],
                "inputTypeIdentifier": "com.apple.Automator.fileSystemObject",
                "outputTypeIdentifier": "com.apple.Automator.nothing",
                "presentationMode": 15,
                "processesInput": 0,
                "serviceApplicationBundleID": "com.apple.finder",
                "serviceApplicationPath": "/System/Library/CoreServices/Finder.app",
                "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
                "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
                "serviceProcessesInput": 0,
                "systemImageName": "NSTouchBarComposeTemplate",
                "useAutomaticInputType": 0,
                "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
            },
        }
        with open(os.path.join(contents, "document.wflow"), "wb") as handle:
            plistlib.dump(workflow, handle)
        print(f"已安装服务：{name}")

    subprocess.run(["/System/Library/CoreServices/pbs", "-update"], check=False)
    print("\n提示：在 Finder 里右键文件 → 快速操作 / 服务 → 万能转码 · 转 XXX")


def uninstall_macos() -> None:
    services = os.path.expanduser("~/Library/Services")
    for name in os.listdir(services) if os.path.isdir(services) else []:
        if name.startswith(SERVICE_PREFIX) and name.endswith(".workflow"):
            shutil.rmtree(os.path.join(services, name), ignore_errors=True)
            print(f"已移除：{name}")
    subprocess.run(["/System/Library/CoreServices/pbs", "-update"], check=False)


# ---------------------------------------------------------------- Windows

def install_windows(formats: list[str]) -> None:
    import winreg

    base = r"Software\Classes\*\shell\AnyConvert"
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, base) as key:
        winreg.SetValueEx(key, "MUIVerb", 0, winreg.REG_SZ, "万能转码")
        winreg.SetValueEx(key, "SubCommands", 0, winreg.REG_SZ, "")
    for target in formats:
        path = rf"{base}\shell\{target}"
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, path) as key:
            winreg.SetValueEx(key, "MUIVerb", 0, winreg.REG_SZ, f"转换为 {target.upper()}")
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, path + r"\command") as key:
            winreg.SetValueEx(key, "", 0, winreg.REG_SZ,
                              f'"{PYTHON}" -m crossplatform.cli convert -i "%1" --to {target}')
        print(f"已安装：转换为 {target.upper()}")


def uninstall_windows() -> None:
    import winreg
    for path in (r"Software\Classes\*\shell\AnyConvert",):
        try:
            winreg.DeleteKey(winreg.HKEY_CURRENT_USER, path + r"\shell\mp4\command")
            winreg.DeleteKey(winreg.HKEY_CURRENT_USER, path + r"\shell\mp4")
        except FileNotFoundError:
            pass
    print("请手动删除 HKCU\\Software\\Classes\\*\\shell\\AnyConvert（或运行 --force）")


# ---------------------------------------------------------------- Linux

def linux_dir() -> str:
    return os.path.expanduser("~/.local/share/nautilus/scripts")


def install_linux(formats: list[str]) -> None:
    directory = os.path.join(linux_dir(), "万能转码")
    os.makedirs(directory, exist_ok=True)
    for target in formats:
        path = os.path.join(directory, f"转为 {target.upper()}")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(f'#!/bin/bash\ncd "{ROOT}" || exit 1\nfor f in "$@"; do\n'
                         f'  "{PYTHON}" -m crossplatform.cli convert -i "$f" --to {target}\n'
                         f'done\n')
        os.chmod(path, 0o755)
        print(f"已安装：{path}")


def uninstall_linux() -> None:
    shutil.rmtree(os.path.join(linux_dir(), "万能转码"), ignore_errors=True)
    print("已移除 Nautilus 脚本")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["install", "uninstall"])
    parser.add_argument("--formats", default=",".join(FORMATS))
    args = parser.parse_args()
    formats = [item.strip().lower() for item in args.formats.split(",") if item.strip()]

    system = platform.system()
    if args.action == "uninstall":
        {"Darwin": uninstall_macos, "Windows": uninstall_windows}.get(system, uninstall_linux)()
        return 0
    if system == "Darwin":
        install_macos(formats)
    elif system == "Windows":
        install_windows(formats)
    else:
        install_linux(formats)
    return 0


if __name__ == "__main__":
    sys.exit(main())
