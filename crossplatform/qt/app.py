"""跨平台桌面版（PySide6/Qt）：合并「飞鼠格式 + File Converter」的能力。

运行：
    python3 -m crossplatform.qt.app
    python3 -m crossplatform.qt.app --demo a.mp4 b.png --autostart
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys

from PySide6.QtCore import QSize, Qt, QTimer
from PySide6.QtGui import QColor, QDragEnterEvent, QDropEvent, QFont, QLinearGradient, QPainter, QPixmap
from PySide6.QtWidgets import (
    QAbstractItemView, QApplication, QCheckBox, QComboBox, QDialog, QDialogButtonBox,
    QDoubleSpinBox, QFileDialog, QFormLayout, QFrame, QGridLayout, QSpinBox,
    QHBoxLayout, QLabel, QLineEdit, QMainWindow, QMessageBox, QProgressBar, QPushButton,
    QSizePolicy, QTabWidget, QTableWidget, QTableWidgetItem, QVBoxLayout, QWidget,
)

from ..core import engines, pdf_tools
from ..core.matrix import MATRIX
from ..core.queue import ConversionQueue

GROUPS = {
    "文档": ["pdf", "docx", "txt", "md", "html", "odt", "rtf", "xlsx", "csv", "pptx"],
    "图片": ["jpg", "png", "webp", "avif", "tiff", "bmp", "ico"],
    "音频": ["mp3", "m4a", "aac", "wav", "flac", "alac", "ogg", "opus", "wma", "aiff", "ac3", "caf"],
    "视频": ["mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv", "flv", "ts", "mpg", "3gp", "ogv", "gif"],
}

PRESETS = [
    ("自定义", None, None),
    ("图片 · 压到 2 MB", "jpg", 2.0),
    ("图片 · 压到 500 KB", "jpg", 0.5),
    ("视频 · 压到 8 MB", "mp4", 8.0),
    ("视频 · 压到 25 MB", "mp4", 25.0),
    ("文档 → PDF", "pdf", None),
    ("音频 → MP3", "mp3", None),
]

DEFAULT_OPTIONS = {
    "resolution": "original", "width": 0, "height": 0,
    "quality": "balanced", "fps": 0, "audio_kbps": 192, "codec": "h264",
}

RESOLUTIONS = [("保持原始", "original"), ("4K", "2160"), ("1080p", "1080"),
               ("720p", "720"), ("480p", "480"), ("360p", "360"), ("自定义", "custom")]
QUALITIES = [("高质量", "high"), ("标准", "balanced"), ("小体积", "small")]
FRAMERATES = [("保持原始", 0), ("60 fps", 60), ("30 fps", 30), ("24 fps", 24)]
AUDIO_RATES = [("128 kbps", 128), ("192 kbps", 192), ("256 kbps", 256), ("320 kbps", 320)]
CODECS = [("H.264", "h264"), ("H.265", "h265"), ("AV1", "av1")]


class SettingsDialog(QDialog):
    """分辨率 / 帧率 / 码率 / 画质 / 编码器。"""

    def __init__(self, parent, options: dict):
        super().__init__(parent)
        self.setWindowTitle("高级设置")
        self.setMinimumWidth(360)
        form = QFormLayout(self)

        self.resolution = QComboBox()
        for label, value in RESOLUTIONS:
            self.resolution.addItem(label, value)

        self.width = QSpinBox()
        self.width.setRange(16, 7680)
        self.width.setValue(options.get("width") or 1920)
        self.height = QSpinBox()
        self.height.setRange(16, 7680)
        self.height.setValue(options.get("height") or 1080)
        custom_row = QHBoxLayout()
        custom_row.addWidget(self.width)
        custom_row.addWidget(QLabel("×"))
        custom_row.addWidget(self.height)

        self.quality = QComboBox()
        for label, value in QUALITIES:
            self.quality.addItem(label, value)
        self.fps = QComboBox()
        for label, value in FRAMERATES:
            self.fps.addItem(label, value)
        self.audio = QComboBox()
        for label, value in AUDIO_RATES:
            self.audio.addItem(label, value)
        self.codec = QComboBox()
        for label, value in CODECS:
            self.codec.addItem(label, value)

        form.addRow("分辨率", self.resolution)
        form.addRow("自定义尺寸", custom_row)
        form.addRow("画质", self.quality)
        form.addRow("帧率", self.fps)
        form.addRow("音频码率", self.audio)
        form.addRow("视频编码", self.codec)

        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.button(QDialogButtonBox.Ok).setText("确定")
        buttons.button(QDialogButtonBox.Cancel).setText("取消")
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        form.addRow(buttons)

        self._load(options)
        self.resolution.currentIndexChanged.connect(self._sync_custom)

    def _load(self, options: dict):
        for combo, key in ((self.resolution, "resolution"), (self.quality, "quality"),
                           (self.fps, "fps"), (self.audio, "audio_kbps"), (self.codec, "codec")):
            index = combo.findData(options.get(key))
            if index >= 0:
                combo.setCurrentIndex(index)
        self._sync_custom()

    def _sync_custom(self):
        custom = self.resolution.currentData() == "custom"
        self.width.setEnabled(custom)
        self.height.setEnabled(custom)

    def values(self) -> dict:
        return {
            "resolution": self.resolution.currentData(),
            "width": self.width.value() if self.resolution.currentData() == "custom" else 0,
            "height": self.height.value() if self.resolution.currentData() == "custom" else 0,
            "quality": self.quality.currentData(),
            "fps": self.fps.currentData(),
            "audio_kbps": self.audio.currentData(),
            "codec": self.codec.currentData(),
        }


STATUS_TEXT = {
    "queued": "等待", "running": "转换中", "done": "完成",
    "failed": "失败", "cancelled": "已取消",
}
STATUS_COLOR = {
    "queued": "#8a8a93", "running": "#4a78fa", "done": "#1aa86b",
    "failed": "#e34949", "cancelled": "#ee9418",
}

QSS = """
* { font-family: "PingFang SC", "Microsoft YaHei", "Segoe UI", sans-serif; }
QMainWindow, #root { background: #f5f6fa; }
#header { background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
           stop:0 #eef2ff, stop:1 #f6f1ff); border-bottom: 1px solid #e3e5ee; }
#title { font-size: 20px; font-weight: 700; color: #1c1c22; }
#tagline { color: #7a7a86; font-size: 12px; }
#engineBadge { background: rgba(74,120,250,0.10); color: #4a5bd0;
               border-radius: 11px; padding: 4px 10px; font-size: 11px; }
#sidebar { background: #ffffff; border: 1px solid #e4e7f0; border-radius: 16px; }
QTabWidget::pane { border: none; background: transparent; }
QTabBar::tab { padding: 7px 9px; margin: 2px; border-radius: 8px;
               color: #6b6b78; font-size: 11px; background: transparent; min-width: 38px; }
QTabBar::tab:selected { background: #eef2ff; color: #4a5bd0; font-weight: 600; }
#groupTitle { color: #8a8a96; font-size: 11px; font-weight: 600; }
QPushButton#target {
    text-align: left; padding: 8px 12px; border-radius: 9px; border: 1px solid transparent;
    background: transparent; color: #33333c; font-size: 13px;
}
QPushButton#target:hover { background: #f0f3ff; }
QPushButton#target[selected="true"] {
    background: #4a78fa; color: white; font-weight: 600;
}
#dropZone {
    background: qlineargradient(x1:0, y1:0, x2:1, y2:1,
                stop:0 rgba(74,120,250,0.09), stop:1 rgba(139,92,246,0.05));
    border: 1.5px dashed rgba(74,120,250,0.45); border-radius: 14px;
}
#dropZone[dragging="true"] { border-color: #4a78fa; background: rgba(74,120,250,0.16); }
#dropTitle { color: #3a3a44; font-size: 14px; font-weight: 600; }
#dropHint { color: #8a8a96; font-size: 11px; }
#error { color: #e34949; font-size: 12px; }
QPushButton#primary {
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 #4a78fa, stop:1 #8b5cf6);
    color: white; font-weight: 600; border: none; border-radius: 9px; padding: 9px 22px;
}
QPushButton#primary:hover { background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
                            stop:0 #5a86ff, stop:1 #9a6ff8); }
QPushButton#primary:disabled { background: #c9cddb; color: #ffffff; }
QPushButton { background: #ffffff; border: 1px solid #dfe2ec; border-radius: 8px;
              padding: 6px 12px; color: #33333c; }
QPushButton:hover { background: #f5f7ff; border-color: #c9d3ff; }
QTableWidget { background: #ffffff; border: 1px solid #e4e7f0; border-radius: 14px;
               gridline-color: transparent; selection-background-color: #edf2ff;
               selection-color: #252b3b; outline: 0; }
QTableWidget::item { padding: 8px; border-bottom: 1px solid #f0f1f6; }
QHeaderView::section { background: #fafbff; color: #8a8a96; border: none;
                       border-bottom: 1px solid #eceef6; padding: 6px; font-size: 11px; }
QProgressBar { border: none; background: #eef0f6; border-radius: 3px; height: 14px;
               text-align: center; color: #33333c; font-size: 10px; }
QProgressBar::chunk { border-radius: 3px;
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 #4a78fa, stop:1 #8b5cf6); }
QComboBox, QLineEdit, QDoubleSpinBox, QSpinBox {
    background: #ffffff; border: 1px solid #dfe2ec; border-radius: 8px; padding: 6px 9px; color: #33333c;
}
QComboBox:focus, QLineEdit:focus, QDoubleSpinBox:focus, QSpinBox:focus { border-color: #4a78fa; }
QCheckBox { color: #44444e; font-size: 12px; }
QLabel#label { color: #6b6b78; font-size: 11px; }
"""


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("万能转码 · 跨平台版")
        self.resize(1120, 740)
        self.move(120, 80)
        self.setMinimumSize(QSize(980, 640))
        self.setAcceptDrops(True)

        self.current_target = "mp4"
        self.options = dict(DEFAULT_OPTIONS)
        self.target_buttons: dict[str, QPushButton] = {}
        self.job_rows: dict[str, int] = {}
        self.output_dir = ""

        self.queue = ConversionQueue(max_workers=3)
        self.queue.on_change = lambda: None  # 由 QTimer 轮询刷新

        root = QWidget(objectName="root")
        self.setCentralWidget(root)
        layout = QVBoxLayout(root)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        layout.addWidget(self._build_header())
        body = QHBoxLayout()
        body.setContentsMargins(16, 14, 16, 10)
        body.setSpacing(14)
        body.addWidget(self._build_sidebar(), 0)
        body.addLayout(self._build_main(), 1)
        layout.addLayout(body, 1)
        layout.addWidget(self._build_footer())

        self.setStyleSheet(QSS)
        self._refresh_targets()
        self._refresh_engines()

        self.timer = QTimer(self)
        self.timer.timeout.connect(self._refresh_queue)
        self.timer.start(400)

    # ---------------------------------------------------------------- UI

    def _build_header(self) -> QWidget:
        header = QWidget(objectName="header")
        header.setFixedHeight(76)
        row = QHBoxLayout(header)
        row.setContentsMargins(18, 10, 18, 10)
        row.setSpacing(12)

        logo = QLabel()
        logo.setFixedSize(38, 38)
        logo.setPixmap(self._logo_pixmap(38))
        row.addWidget(logo)

        text = QVBoxLayout()
        text.setSpacing(1)
        title = QLabel("万能转码", objectName="title")
        tagline = QLabel("文档 · 图片 · 音视频  批量转换 / 按目标体积压缩", objectName="tagline")
        text.addWidget(title)
        text.addWidget(tagline)
        row.addLayout(text)
        row.addStretch(1)

        self.engine_badge = QLabel(objectName="engineBadge")
        row.addWidget(self.engine_badge)
        return header

    def _build_sidebar(self) -> QWidget:
        card = QFrame(objectName="sidebar")
        card.setFixedWidth(240)
        outer = QVBoxLayout(card)
        outer.setContentsMargins(8, 8, 8, 8)
        outer.setSpacing(4)

        tabs = QTabWidget(objectName="targetTabs")
        self.tabs = tabs
        tabs.setElideMode(Qt.ElideNone)
        tabs.setUsesScrollButtons(False)
        tabs.setDocumentMode(True)
        for group, targets in GROUPS.items():
            page = QWidget()
            grid = QGridLayout(page)
            grid.setContentsMargins(4, 8, 4, 4)
            grid.setSpacing(4)
            for index, target in enumerate(targets):
                button = QPushButton(target.upper(), objectName="target")
                button.setToolTip(f".{target} · {len(MATRIX.sources(target))} 种源格式")
                button.setCursor(Qt.PointingHandCursor)
                button.clicked.connect(lambda _=False, t=target: self._select_target(t))
                self.target_buttons[target] = button
                grid.addWidget(button, index // 2, index % 2)
            grid.setRowStretch(grid.rowCount(), 1)
            tabs.addTab(page, group)

        tools = QWidget()
        tool_layout = QVBoxLayout(tools)
        tool_layout.setContentsMargins(6, 10, 6, 6)
        tool_layout.setSpacing(6)
        for label, handler in (
            ("合并 PDF", self.merge_pdfs),
            ("拆分 PDF", self.split_pdf),
            ("PDF 转图片 (ZIP)", self.pdf_images),
            ("PDF 表格转 Excel", self.pdf_tables),
            ("图片转 PDF", self.images_to_pdf),
        ):
            button = QPushButton(label)
            button.setCursor(Qt.PointingHandCursor)
            button.clicked.connect(handler)
            tool_layout.addWidget(button)

        level_row = QHBoxLayout()
        level_row.addWidget(QLabel("ZIP 级别", objectName="label"))
        self.zip_level = QSpinBox()
        self.zip_level.setRange(0, 9)
        self.zip_level.setValue(6)
        level_row.addWidget(self.zip_level)
        level_row.addStretch(1)
        tool_layout.addLayout(level_row)

        zip_button = QPushButton("打包 ZIP")
        zip_button.setCursor(Qt.PointingHandCursor)
        zip_button.clicked.connect(self.zip_files)
        tool_layout.addWidget(zip_button)
        tool_layout.addStretch(1)
        tabs.addTab(tools, "工具")
        outer.addWidget(tabs)
        return card

    def _build_main(self) -> QVBoxLayout:
        column = QVBoxLayout()
        column.setSpacing(10)

        self.drop_zone = QFrame(objectName="dropZone")
        self.drop_zone.setProperty("dragging", False)
        self.drop_zone.setMinimumHeight(120)
        self.drop_zone.setCursor(Qt.PointingHandCursor)
        drop_layout = QVBoxLayout(self.drop_zone)
        drop_layout.setAlignment(Qt.AlignCenter)
        drop_layout.setSpacing(4)
        title = QLabel("把文件拖到这里", objectName="dropTitle")
        title.setAlignment(Qt.AlignCenter)
        hint = QLabel("批量拖入会自动校验格式；不支持的类型会红字提示", objectName="dropHint")
        hint.setAlignment(Qt.AlignCenter)
        drop_layout.addWidget(title)
        drop_layout.addWidget(hint)

        buttons = QHBoxLayout()
        buttons.setAlignment(Qt.AlignCenter)
        pick_files = QPushButton("选择文件")
        pick_files.clicked.connect(self.pick_files)
        pick_folder = QPushButton("选择文件夹")
        pick_folder.clicked.connect(self.pick_folder)
        buttons.addWidget(pick_files)
        buttons.addWidget(pick_folder)
        drop_layout.addLayout(buttons)
        self.drop_zone.mousePressEvent = lambda _event: self.pick_files()
        column.addWidget(self.drop_zone)

        self.error_label = QLabel("", objectName="error")
        self.error_label.setVisible(False)
        column.addWidget(self.error_label)

        self.empty_hint = QLabel("还没有文件 · 拖入或点击「选择文件」", objectName="label")
        self.empty_hint.setAlignment(Qt.AlignCenter)
        column.addWidget(self.empty_hint)

        self.table = QTableWidget(0, 5)
        self.table.setHorizontalHeaderLabels(["文件", "目标", "状态", "进度", "说明"])
        self.table.verticalHeader().setVisible(False)
        self.table.horizontalHeader().setStretchLastSection(True)
        self.table.setColumnWidth(0, 300)
        self.table.setColumnWidth(1, 60)
        self.table.setColumnWidth(2, 80)
        self.table.setColumnWidth(3, 120)
        self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.table.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.table.cellDoubleClicked.connect(self._open_output)
        column.addWidget(self.table, 1)
        return column

    def _build_footer(self) -> QWidget:
        footer = QWidget()
        footer.setStyleSheet("background: #ffffff; border-top: 1px solid #e6e8f0;")
        outer = QVBoxLayout(footer)
        outer.setContentsMargins(16, 8, 16, 10)
        outer.setSpacing(6)

        row1 = QHBoxLayout()
        row1.setSpacing(8)
        row1.addWidget(QLabel("预设", objectName="label"))
        self.preset_box = QComboBox()
        for name, _target, _size in PRESETS:
            self.preset_box.addItem(name)
        self.preset_box.currentIndexChanged.connect(self._apply_preset)
        row1.addWidget(self.preset_box)

        self.size_check = QCheckBox("限制体积")
        self.size_check.toggled.connect(self._toggle_size)
        row1.addWidget(self.size_check)

        self.size_spin = QDoubleSpinBox()
        self.size_spin.setRange(0.1, 500.0)
        self.size_spin.setSingleStep(0.5)
        self.size_spin.setValue(2.0)
        self.size_spin.setSuffix(" MB")
        self.size_spin.setFixedWidth(96)
        self.size_spin.setEnabled(False)
        row1.addWidget(self.size_spin)

        self.downscale_check = QCheckBox("允许降低分辨率")
        self.downscale_check.setChecked(True)
        self.downscale_check.setEnabled(False)
        row1.addWidget(self.downscale_check)

        row1.addSpacing(10)
        self.settings_button = QPushButton("高级设置")
        self.settings_button.clicked.connect(self.open_settings)
        row1.addWidget(self.settings_button)
        self.settings_summary = QLabel("1080p · 标准 · 原始帧率 · 192k · H.264", objectName="label")
        row1.addWidget(self.settings_summary)

        row1.addSpacing(12)
        row1.addWidget(QLabel("并行", objectName="label"))
        self.workers_spin = QSpinBox()
        self.workers_spin.setRange(1, 8)
        self.workers_spin.setValue(3)
        self.workers_spin.setFixedWidth(64)
        self.workers_spin.setSuffix(" 个")
        self.workers_spin.valueChanged.connect(self.queue.set_max_workers)
        row1.addWidget(self.workers_spin)
        row1.addStretch(1)
        outer.addLayout(row1)

        row2 = QHBoxLayout()
        row2.setSpacing(8)
        self.summary = QLabel("还没有文件", objectName="label")
        row2.addWidget(self.summary)
        row2.addStretch(1)

        choose_out = QPushButton("输出目录")
        choose_out.clicked.connect(self.pick_output_dir)
        row2.addWidget(choose_out)

        self.cancel_button = QPushButton("取消")
        self.cancel_button.clicked.connect(self.queue.cancel)
        self.cancel_button.setEnabled(False)
        row2.addWidget(self.cancel_button)

        self.start_button = QPushButton("开始转换", objectName="primary")
        self.start_button.clicked.connect(self.start)
        self.start_button.setMinimumWidth(118)
        # 显式内联样式，避免全局 QSS 的 id 选择器在部分平台被覆盖
        self.start_button.setStyleSheet("""
            QPushButton { background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
                          stop:0 #4a78fa, stop:1 #8b5cf6);
                          color: white; font-weight: 600; border: none;
                          border-radius: 9px; padding: 9px 22px; }
            QPushButton:hover { background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
                                stop:0 #5a86ff, stop:1 #9a6ff8); }
            QPushButton:disabled { background: #c9cddb; color: white; }
        """)
        row2.addWidget(self.start_button)
        outer.addLayout(row2)
        return footer

    # ---------------------------------------------------------------- 行为

    def _logo_pixmap(self, size: int) -> QPixmap:
        pixmap = QPixmap(size, size)
        pixmap.fill(Qt.transparent)
        painter = QPainter(pixmap)
        painter.setRenderHint(QPainter.Antialiasing)
        gradient = QLinearGradient(0, 0, size, size)
        gradient.setColorAt(0, QColor("#4a78fa"))
        gradient.setColorAt(1, QColor("#8b5cf6"))
        painter.setBrush(gradient)
        painter.setPen(Qt.NoPen)
        painter.drawRoundedRect(0, 0, size, size, 10, 10)
        painter.setPen(QColor("white"))
        font = QFont()
        font.setPointSize(int(size * 0.42))
        font.setBold(True)
        painter.setFont(font)
        painter.drawText(pixmap.rect(), Qt.AlignCenter, "⇄")
        painter.end()
        return pixmap

    def _refresh_engines(self):
        status = engines.engine_status()
        parts = []
        for name, label in (("ffmpeg", "FFmpeg"), ("libreoffice", "LibreOffice"),
                            ("ocr", "OCR")):
            info = status[name]
            parts.append(f"{label} {'●' if info['available'] else '○'}")
        self.engine_badge.setText("  ".join(parts))
        self.engine_badge.setToolTip(
            "\n".join(f"{k}: {v['path'] or '未安装'}" for k, v in status.items())
        )

    def _refresh_targets(self):
        for target, button in self.target_buttons.items():
            selected = target == self.current_target
            button.setProperty("selected", selected)
            button.style().unpolish(button)
            button.style().polish(button)
        self.setWindowTitle(f"万能转码 · 跨平台版 — 目标 .{self.current_target}")

    def _select_target(self, target: str):
        self.current_target = target
        self._refresh_targets()
        self._refresh_queue()

    def _apply_preset(self, index: int):
        _name, target, size = PRESETS[index]
        if target:
            self._select_target(target)
        if size is None:
            self.size_check.setChecked(False)
        else:
            self.size_check.setChecked(True)
            self.size_spin.setValue(size)
            if target in ("jpg", "png", "webp"):
                self.downscale_check.setChecked(True)

    def open_settings(self):
        dialog = SettingsDialog(self, self.options)
        if dialog.exec() == QDialog.Accepted:
            self.options = dialog.values()
            self._refresh_settings_summary()

    def _refresh_settings_summary(self):
        options = self.options
        res = dict(RESOLUTIONS).get(options["resolution"], "保持原始")
        if options["resolution"] == "custom":
            res = f'{options["width"]}×{options["height"]}'
        quality = dict(QUALITIES).get(options["quality"], "标准")
        fps = options["fps"] or "原始帧率"
        codec = dict(CODECS).get(options["codec"], "H.264")
        self.settings_summary.setText(
            f"{res} · {quality} · {fps} · {options['audio_kbps']}k · {codec}"
        )

    def _toggle_size(self, enabled: bool):
        self.size_spin.setEnabled(enabled)
        self.downscale_check.setEnabled(enabled)

    def _target_bytes(self):
        if not self.size_check.isChecked():
            return None
        return int(self.size_spin.value() * 1024 * 1024)

    def pick_files(self):
        paths, _ = QFileDialog.getOpenFileNames(self, f"选择要转换为 .{self.current_target} 的文件")
        if paths:
            self.add_paths(paths)

    def pick_folder(self):
        folder = QFileDialog.getExistingDirectory(self, "选择文件夹")
        if folder:
            self.add_paths([os.path.join(folder, n) for n in os.listdir(folder)
                            if os.path.isfile(os.path.join(folder, n))])

    def pick_output_dir(self):
        folder = QFileDialog.getExistingDirectory(self, "选择输出目录")
        if folder:
            self.output_dir = folder
            self.queue.output_dir = folder
            self.summary.setText(f"输出到：{folder}")

    def add_paths(self, paths):
        accepted, rejected = self.queue.add(paths, self.current_target, self._target_bytes(),
                                            self.options["codec"], self.options)
        if rejected:
            first = rejected[0]
            extra = f"（另有 {len(rejected) - 1} 个同样被拒绝）" if len(rejected) > 1 else ""
            self._show_error(first.reason + extra)
        else:
            self._show_error("")
        self._refresh_queue()

    def _show_error(self, text: str):
        self.error_label.setText(text)
        self.error_label.setVisible(bool(text))

    def start(self):
        count = self.queue.start()
        if count == 0:
            self._show_error("没有待转换的文件，或队列正在运行")
        self._refresh_queue()

    # ---------------------------------------------------------------- 工具

    def merge_pdfs(self):
        paths, _ = QFileDialog.getOpenFileNames(self, "选择要合并的 PDF", "", "PDF (*.pdf)")
        if not paths:
            return
        output, _ = QFileDialog.getSaveFileName(self, "合并后保存为", "merged.pdf", "PDF (*.pdf)")
        if not output:
            return
        try:
            pdf_tools.merge_pdfs(paths, output)
            QMessageBox.information(self, "完成", f"已合并 {len(paths)} 个 PDF：\n{output}")
        except Exception as exc:  # noqa: BLE001
            QMessageBox.warning(self, "合并失败", str(exc))

    def split_pdf(self):
        path, _ = QFileDialog.getOpenFileName(self, "选择要拆分的 PDF", "", "PDF (*.pdf)")
        if not path:
            return
        folder = QFileDialog.getExistingDirectory(self, "选择输出文件夹")
        if not folder:
            return
        try:
            result = pdf_tools.split_pdf(path, folder, every=1)
            QMessageBox.information(self, "完成", f"拆分结果：\n{result}")
        except Exception as exc:  # noqa: BLE001
            QMessageBox.warning(self, "拆分失败", str(exc))

    def images_to_pdf(self):
        paths, _ = QFileDialog.getOpenFileNames(self, "选择图片", "", "图片 (*.jpg *.jpeg *.png *.webp *.bmp *.tif *.tiff)")
        if not paths:
            return
        output, _ = QFileDialog.getSaveFileName(self, "保存为", "album.pdf", "PDF (*.pdf)")
        if not output:
            return
        try:
            pdf_tools.images_to_pdf(paths, output)
            QMessageBox.information(self, "完成", f"已生成：\n{output}")
        except Exception as exc:  # noqa: BLE001
            QMessageBox.warning(self, "生成失败", str(exc))

    def pdf_images(self):
        path, _ = QFileDialog.getOpenFileName(self, "选择 PDF", "", "PDF (*.pdf)")
        if not path:
            return
        folder = QFileDialog.getExistingDirectory(self, "选择输出文件夹")
        if not folder:
            return
        try:
            result = pdf_tools.pdf_to_images_zip(path, folder, level=self.zip_level.value())
            QMessageBox.information(self, "完成", f"已导出：\n{result}")
        except Exception as exc:  # noqa: BLE001
            QMessageBox.warning(self, "导出失败", str(exc))

    def pdf_tables(self):
        path, _ = QFileDialog.getOpenFileName(self, "选择 PDF", "", "PDF (*.pdf)")
        if not path:
            return
        output, _ = QFileDialog.getSaveFileName(self, "保存为", "tables.xlsx", "Excel (*.xlsx)")
        if not output:
            return
        try:
            pdf_tools.pdf_tables_to_xlsx(path, output)
            QMessageBox.information(self, "完成", f"已提取表格：\n{output}")
        except Exception as exc:  # noqa: BLE001
            QMessageBox.warning(self, "提取失败", str(exc))

    def zip_files(self):
        paths, _ = QFileDialog.getOpenFileNames(self, "选择要打包的文件")
        if not paths:
            return
        output, _ = QFileDialog.getSaveFileName(self, "保存为", "archive.zip", "ZIP (*.zip)")
        if not output:
            return
        try:
            engines.zip_files(paths, output, self.zip_level.value())
            QMessageBox.information(self, "完成", f"已打包 {len(paths)} 个文件：\n{output}")
        except Exception as exc:  # noqa: BLE001
            QMessageBox.warning(self, "打包失败", str(exc))

    # ---------------------------------------------------------------- 拖拽

    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            self.drop_zone.setProperty("dragging", True)
            self.drop_zone.style().unpolish(self.drop_zone)
            self.drop_zone.style().polish(self.drop_zone)
            event.acceptProposedAction()

    def dragLeaveEvent(self, event):
        self.drop_zone.setProperty("dragging", False)
        self.drop_zone.style().unpolish(self.drop_zone)
        self.drop_zone.style().polish(self.drop_zone)

    def dropEvent(self, event: QDropEvent):
        self.drop_zone.setProperty("dragging", False)
        self.drop_zone.style().unpolish(self.drop_zone)
        self.drop_zone.style().polish(self.drop_zone)
        paths = [url.toLocalFile() for url in event.mimeData().urls() if url.isLocalFile()]
        if paths:
            self.add_paths(paths)
            event.acceptProposedAction()

    # ---------------------------------------------------------------- 队列刷新

    def _refresh_queue(self):
        jobs = self.queue.snapshot()
        stats = self.queue.stats()
        self.summary.setText(
            f"共 {stats['total']} 个 · 完成 {stats['done']} · 失败 {stats['failed']}"
            f" · 并行 {stats['running']}/{self.queue.max_workers}"
        )
        self.start_button.setEnabled(stats["queued"] > 0)
        self.cancel_button.setEnabled(stats["running"] > 0 or stats["queued"] > 0)

        self.empty_hint.setVisible(len(jobs) == 0)
        self.table.setRowCount(len(jobs))
        self.job_rows = {}
        for row, job in enumerate(jobs):
            self.job_rows[job["id"]] = row
            name = os.path.basename(job["src"])
            self.table.setItem(row, 0, QTableWidgetItem(name))
            self.table.setItem(row, 1, QTableWidgetItem("." + job["target"]))
            status_item = QTableWidgetItem(STATUS_TEXT.get(job["status"], job["status"]))
            status_item.setForeground(QColor(STATUS_COLOR.get(job["status"], "#333")))
            self.table.setItem(row, 2, status_item)

            bar = QProgressBar()
            bar.setRange(0, 100)
            bar.setValue(int(job["progress"] * 100))
            bar.setTextVisible(True)
            bar.setFixedHeight(14)
            self.table.setCellWidget(row, 3, bar)

            detail = job["error"] or (os.path.basename(job["output"]) if job["output"] else "")
            if job["status"] == "running":
                detail = f"{job.get('elapsed', 0):.0f}s"
            self.table.setItem(row, 4, QTableWidgetItem(detail))

    def _open_output(self, row: int, _column: int):
        item = self.table.item(row, 4)
        if not item or not item.text():
            return
        path = item.text()
        for job in self.queue.snapshot():
            if job["output"] and os.path.basename(job["output"]) == path:
                folder = os.path.dirname(job["output"])
                if sys.platform == "darwin":
                    subprocess.Popen(["open", folder])
                elif os.name == "nt":
                    os.startfile(folder)  # noqa: S606
                else:
                    subprocess.Popen(["xdg-open", folder])
                return


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="*")
    parser.add_argument("--target", default="mp4")
    parser.add_argument("--autostart", action="store_true")
    parser.add_argument("--demo", nargs="*", default=None)
    parser.add_argument("--tools", action="store_true")
    parser.add_argument("--settings", action="store_true")
    args = parser.parse_args()

    app = QApplication(sys.argv)
    window = MainWindow()
    window._select_target(args.target)
    window.show()
    if args.tools:
        window.tabs.setCurrentIndex(window.tabs.count() - 1)
    if args.settings:
        QTimer.singleShot(500, window.open_settings)

    demo_files = args.demo if args.demo is not None else args.files
    if demo_files:
        QTimer.singleShot(400, lambda: window.add_paths(demo_files))
    if args.autostart:
        QTimer.singleShot(1200, window.start)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
