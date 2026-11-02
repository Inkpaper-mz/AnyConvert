"""命令行入口：批处理 / 右键菜单 / 自动化。

示例：
    python3 -m crossplatform.cli convert -i a.mp4 --to mp3 --json
    python3 -m crossplatform.cli convert -i a.jpg --to jpg --target-size 2
    python3 -m crossplatform.cli merge-pdfs a.pdf b.pdf -o out.pdf
    python3 -m crossplatform.cli capabilities --json
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from .core import engines, pdf_tools
from .core.matrix import MATRIX


def _out_dir(path: str | None, src: str) -> str:
    return os.path.abspath(path) if path else os.path.dirname(os.path.abspath(src))


def cmd_convert(args) -> int:
    target = args.to.lower().lstrip(".")
    out_dir = _out_dir(args.output_dir, args.input)
    options = {
        "resolution": args.resolution,
        "width": args.width or 0,
        "height": args.height or 0,
        "quality": args.quality,
        "fps": args.fps or 0,
        "audio_kbps": args.audio_kbps,
    }
    target_bytes = int(args.target_size * 1024 * 1024) if args.target_size else None
    try:
        output = engines.convert(args.input, target, out_dir,
                                 target_bytes=target_bytes,
                                 codec=args.codec, options=options)
    except Exception as exc:  # noqa: BLE001
        if args.json:
            print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        else:
            print(f"失败：{exc}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps({"ok": True, "output": output,
                          "bytes": os.path.getsize(output)}, ensure_ascii=False))
    else:
        print(output)
    return 0


def cmd_capabilities(args) -> int:
    payload = {
        "targets": {name: {"category": spec.get("category"),
                           "sources": spec.get("sources")}
                    for name, spec in MATRIX.targets.items()},
        "engines": engines.engine_status(),
    }
    if args.json:
        print(json.dumps(payload, ensure_ascii=False))
    else:
        for name, spec in sorted(payload["targets"].items()):
            print(f"{name:6s} {spec['category']:12s} {len(spec['sources'])} 种源格式")
    return 0


def cmd_merge_pdfs(args) -> int:
    try:
        pdf_tools.merge_pdfs(args.inputs, args.output)
    except Exception as exc:  # noqa: BLE001
        print(f"失败：{exc}", file=sys.stderr)
        return 1
    print(args.output)
    return 0


def cmd_split_pdf(args) -> int:
    try:
        result = pdf_tools.split_pdf(args.input, args.output_dir or os.path.dirname(os.path.abspath(args.input)),
                                     every=args.every)
    except Exception as exc:  # noqa: BLE001
        print(f"失败：{exc}", file=sys.stderr)
        return 1
    print(result)
    return 0


def cmd_images_to_pdf(args) -> int:
    try:
        pdf_tools.images_to_pdf(args.inputs, args.output)
    except Exception as exc:  # noqa: BLE001
        print(f"失败：{exc}", file=sys.stderr)
        return 1
    print(args.output)
    return 0


def cmd_pdf_tables(args) -> int:
    try:
        pdf_tools.pdf_tables_to_xlsx(args.input, args.output)
    except Exception as exc:  # noqa: BLE001
        print(f"失败：{exc}", file=sys.stderr)
        return 1
    print(args.output)
    return 0


def cmd_zip(args) -> int:
    try:
        output = engines.zip_files(args.inputs, args.output, args.level)
    except Exception as exc:  # noqa: BLE001
        print(f"失败：{exc}", file=sys.stderr)
        return 1
    print(output)
    return 0


def cmd_pdf_images(args) -> int:
    try:
        output = pdf_tools.pdf_to_images_zip(args.input, args.output_dir or os.path.dirname(os.path.abspath(args.input)),
                                             fmt=args.format, dpi=args.dpi, level=args.level)
    except Exception as exc:  # noqa: BLE001
        print(f"失败：{exc}", file=sys.stderr)
        return 1
    print(output)
    return 0


def build_parser() -> argparse.ArgumentParser:
    from . import __version__
    parser = argparse.ArgumentParser(prog="anyconvert", description="万能转码 · 跨平台 CLI")
    parser.add_argument("--version", action="version", version=f"anyconvert {__version__}")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("convert", help="转换 / 压缩单个文件")
    p.add_argument("-i", "--input", required=True)
    p.add_argument("--to", required=True)
    p.add_argument("-o", "--output-dir")
    p.add_argument("--target-size", type=float, help="目标体积（MB）")
    p.add_argument("--resolution", default="original")
    p.add_argument("--width", type=int)
    p.add_argument("--height", type=int)
    p.add_argument("--quality", default="balanced", choices=["high", "balanced", "small"])
    p.add_argument("--fps", type=int, default=0)
    p.add_argument("--audio-kbps", type=int, default=192)
    p.add_argument("--codec", default="h264", choices=["h264", "h265", "av1"])
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_convert)

    p = sub.add_parser("capabilities", help="列出目标格式与引擎状态")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_capabilities)

    p = sub.add_parser("merge-pdfs")
    p.add_argument("inputs", nargs="+")
    p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_merge_pdfs)

    p = sub.add_parser("split-pdf")
    p.add_argument("input")
    p.add_argument("-d", "--output-dir")
    p.add_argument("--every", type=int, default=1)
    p.set_defaults(func=cmd_split_pdf)

    p = sub.add_parser("images-to-pdf")
    p.add_argument("inputs", nargs="+")
    p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_images_to_pdf)

    p = sub.add_parser("pdf-tables")
    p.add_argument("input")
    p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_pdf_tables)

    p = sub.add_parser("pdf-images")
    p.add_argument("input")
    p.add_argument("-d", "--output-dir")
    p.add_argument("--format", default="png", choices=["png", "jpg"])
    p.add_argument("--dpi", type=int, default=150)
    p.add_argument("--level", type=int, default=6)
    p.set_defaults(func=cmd_pdf_images)

    p = sub.add_parser("zip")
    p.add_argument("inputs", nargs="+")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--level", type=int, default=6)
    p.set_defaults(func=cmd_zip)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
