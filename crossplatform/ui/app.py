"""Tkinter 工作区界面：目标格式标签页 → 独立工作区窗口 → 批量拖拽 → 校验入队。

依赖：标准库 tkinter；拖拽额外需要 tkinterdnd2（没有则自动降级为按钮选择）。
运行：python3 -m crossplatform.ui.app
"""

from __future__ import annotations

import os
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from ..core import engines
from ..core.matrix import MATRIX
from ..core.queue import ConversionQueue

try:  # 可选依赖：拖拽支持
    from tkinterdnd2 import DND_FILES, TkinterDnD
    HAS_DND = True
except Exception:  # noqa: BLE001
    HAS_DND = False
    DND_FILES = None
    TkinterDnD = None

GROUPS = {
    "文档": ["pdf", "docx", "txt", "md", "html"],
    "图片": ["jpg", "png", "webp", "avif", "tiff", "bmp", "ico"],
    "音视频": ["mp3", "m4a", "wav", "flac", "ogg", "opus", "mp4", "mov", "mkv", "webm", "gif"],
}


class Workspace:
    """一个目标格式对应的工作区窗口。"""

    def __init__(self, app: "AnyConvertApp", target: str):
        self.app = app
        self.target = target
        self.win = tk.Toplevel(app.root)
        self.win.title(f"转换为 .{target} — 工作区")
        self.win.geometry("760x520+%d+%d" % (app.root.winfo_x() + 60, app.root.winfo_y() + 60))
        self.win.lift()
        self.win.focus_force()
        self.win.minsize(620, 420)

        outer = ttk.Frame(self.win, padding=12)
        outer.pack(fill="both", expand=True)

        header = ttk.Frame(outer)
        header.pack(fill="x")
        ttk.Label(header, text=f"目标格式：.{target}",
                  font=("PingFang SC", 14, "bold")).pack(side="left")
        ttk.Label(header, text=f"允许 {len(MATRIX.sources(target))} 种源格式",
                  foreground="#6b6b72").pack(side="left", padx=8)
        ttk.Button(header, text="选择文件", command=self.pick_files).pack(side="right")
        ttk.Button(header, text="选择文件夹", command=self.pick_folder).pack(side="right", padx=6)

        size_row = ttk.Frame(outer)
        size_row.pack(fill="x", pady=(6, 0))
        ttk.Label(size_row, text="目标大小 (MB)：").pack(side="left")
        self.size_entry = ttk.Entry(size_row, width=10)
        self.size_entry.pack(side="left")
        ttk.Label(size_row, text="留空 = 普通转换；填写后自动压缩到不超过该体积",
                  foreground="#6b6b72").pack(side="left", padx=6)
        if MATRIX.category(target) not in ("image", "video"):
            self.size_entry.state(["disabled"])

        self.drop = tk.Label(
            outer, height=3, relief="groove", bd=1, justify="center",
            text=("把文件拖到这里（支持批量）" if HAS_DND else "把文件拖到这里需要 tkinterdnd2；可先用上方按钮选择"),
            fg="#4a78fa", bg="#f4f6ff",
        )
        self.drop.pack(fill="x", pady=8)
        if HAS_DND:
            self.drop.drop_target_register(DND_FILES)
            self.drop.dnd_bind("<<Drop>>", self._on_drop)

        self.error = tk.Label(outer, text="", fg="#e34949", anchor="w", justify="left")
        self.error.pack(fill="x")

        columns = ("name", "status", "progress", "detail")
        self.tree = ttk.Treeview(outer, columns=columns, show="headings", height=12)
        for key, title, width in (("name", "文件", 260), ("status", "状态", 90),
                                  ("progress", "进度", 80), ("detail", "说明", 280)):
            self.tree.heading(key, text=title)
            self.tree.column(key, width=width, anchor="w")
        self.tree.pack(fill="both", expand=True, pady=6)

        bottom = ttk.Frame(outer)
        bottom.pack(fill="x")
        self.summary = ttk.Label(bottom, text="还没有文件")
        self.summary.pack(side="left")
        ttk.Button(bottom, text="清空已完成", command=self.clear_done).pack(side="right", padx=6)
        ttk.Button(bottom, text="取消", command=self.cancel).pack(side="right", padx=6)
        ttk.Button(bottom, text="开始转换", command=self.start).pack(side="right")

        self.job_rows: dict[str, str] = {}
        self.refresh()

    # ---- 添加与校验 ------------------------------------------
    def pick_files(self):
        paths = filedialog.askopenfilenames(title=f"选择要转换为 .{self.target} 的文件")
        if paths:
            self.add_paths(list(paths))

    def pick_folder(self):
        folder = filedialog.askdirectory(title="选择文件夹")
        if not folder:
            return
        paths = []
        for name in os.listdir(folder):
            full = os.path.join(folder, name)
            if os.path.isfile(full):
                paths.append(full)
        self.add_paths(paths)

    def _on_drop(self, event):
        try:
            paths = list(self.win.tk.splitlist(event.data))
        except Exception:  # noqa: BLE001
            paths = [event.data]
        self.add_paths(paths)

    def target_bytes(self) -> int | None:
        raw = self.size_entry.get().strip()
        if not raw:
            return None
        try:
            mb = float(raw)
        except ValueError:
            self.show_error("目标大小需要填写数字（单位 MB）")
            return None
        if mb <= 0:
            return None
        return int(mb * 1024 * 1024)

    def add_paths(self, paths: list[str]):
        accepted, rejected = self.app.queue.add(paths, self.target, self.target_bytes())
        if rejected:
            first = rejected[0]
            extra = f"（另有 {len(rejected) - 1} 个文件同样被拒绝）" if len(rejected) > 1 else ""
            self.show_error(first.reason + extra)
        else:
            self.show_error("")
        self.refresh()

    def show_error(self, text: str):
        self.error.config(text=text)

    # ---- 执行 ------------------------------------------------
    def start(self):
        count = self.app.queue.start()
        if count == 0:
            self.show_error("队列里没有待转换的文件")
        self.refresh()

    def cancel(self):
        self.app.queue.cancel()
        self.refresh()

    def clear_done(self):
        self.app.queue.clear_finished()
        self.refresh()

    # ---- 刷新 ------------------------------------------------
    def refresh(self):
        if not self.win.winfo_exists():
            return
        jobs = self.app.queue.snapshot(self.target)
        seen = set()
        for job in jobs:
            seen.add(job["id"])
            values = (os.path.basename(job["src"]),
                      {"queued": "等待", "running": "转换中", "done": "完成",
                       "failed": "失败", "cancelled": "已取消"}.get(job["status"], job["status"]),
                      f"{int(job['progress'] * 100)}%",
                      job["error"] or (job["output"] and os.path.basename(job["output"])) or "")
            if job["id"] in self.job_rows:
                self.tree.item(self.job_rows[job["id"]], values=values)
            else:
                self.job_rows[job["id"]] = self.tree.insert("", "end", values=values)
        for job_id, item in list(self.job_rows.items()):
            if job_id not in seen:
                self.tree.delete(item)
                self.job_rows.pop(job_id, None)

        stats = self.app.queue.stats()
        self.summary.config(text=f"共 {stats['total']} 个 · 完成 {stats['done']} · 失败 {stats['failed']}"
                                f" · 并行 {stats['running']}/{self.app.queue.max_workers}")
        self.win.after(400, self.refresh)


class AnyConvertApp:
    def __init__(self):
        if HAS_DND:
            self.root = TkinterDnD.Tk()
        else:
            self.root = tk.Tk()
        self.root.title("万能转码 · 跨平台版")
        self.root.geometry("720x300")

        self.queue = ConversionQueue(max_workers=3)
        self.workspaces: dict[str, Workspace] = {}

        ttk.Label(self.root, text="万能转码", font=("PingFang SC", 18, "bold")).pack(anchor="w", padx=16, pady=(14, 0))
        ttk.Label(self.root, text="选择一个目标格式，打开独立工作区；批量拖入文件，自动校验后入队（并发 3）",
                  foreground="#6b6b72").pack(anchor="w", padx=16, pady=(2, 10))

        status = engines.engine_status()
        text = "  ".join(
            f"{name}: {'已就绪' if info['available'] else '未安装'}"
            for name, info in status.items()
        )
        ttk.Label(self.root, text=text, foreground="#6b6b72").pack(anchor="w", padx=16)

        notebook = ttk.Notebook(self.root)
        notebook.pack(fill="both", expand=True, padx=16, pady=12)
        for group, targets in GROUPS.items():
            frame = ttk.Frame(notebook)
            notebook.add(frame, text=group)
            for target in targets:
                ttk.Button(frame, text=f".{target}", width=8,
                           command=lambda t=target: self.open_workspace(t)).pack(side="left", padx=4, pady=12)

        self.root.after(500, self._tick)

    def open_workspace(self, target: str):
        workspace = self.workspaces.get(target)
        if workspace and workspace.win.winfo_exists():
            workspace.win.lift()
            return
        self.workspaces[target] = Workspace(self, target)

    def _tick(self):
        for workspace in list(self.workspaces.values()):
            if workspace.win.winfo_exists():
                workspace.refresh()
        self.root.after(800, self._tick)


def main():
    app = AnyConvertApp()
    app.root.mainloop()


if __name__ == "__main__":
    main()
