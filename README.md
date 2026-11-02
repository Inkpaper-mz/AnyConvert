# 万能转码 · AnyConvert 1.5.0

全平台离线格式转换器：**三平台统一本地 Web UI**（macOS 另提供原生版）。
43 种目标格式（文档 / 图片 / 音频 / 视频），支持按目标体积压缩；
自带 FFmpeg、LibreOffice 与 OCR 引擎，全部在本机完成，不联网、不上传。

![Web UI](docs/webui.png)

## 右键菜单

```bash
python3 scripts/install_context_menu.py install                 # 安装全部格式
python3 scripts/install_context_menu.py install --formats pdf,mp3
python3 scripts/install_context_menu.py uninstall
```

- **macOS**：写入 `~/Library/Services/万能转码 · 转 XXX.workflow`（Finder 快速操作 / 服务），调用 CLI，转换完成弹系统通知
- **Windows**：写入 `HKCU\Software\Classes\*\shell\AnyConvert` 级联菜单
- **Linux**：写入 `~/.local/share/nautilus/scripts/万能转码/`

转换结果输出到源文件所在目录；失败时查看仓库根目录 `service.log`。

## 跨平台 Web 版（推荐）

用本地 Web UI 取代 Qt 界面：样式完全可控、三大平台一致、无需安装客户端。

```bash
python3 -m webui.server          # 自动打开浏览器（仅监听 127.0.0.1）
bash scripts/run_web.sh --port 8899 --no-browser
```

![Web UI](docs/webui.png)

功能：43 种目标格式、拖拽/文件夹批量、目标体积压缩、分辨率/帧率/码率/编码器、并行 1–8、
PDF 合并/拆分/转图片/表格转 Excel/图片转 PDF/ZIP 打包、引擎状态（FFmpeg / LibreOffice / OCR）。

后端：`webui/server.py`；前端：`webui/static/`（原生 HTML/CSS/JS，无构建步骤）。

## 功能

- **32 种输出格式**：13 种视频 + 12 种音频 + 7 种图片，输入由 FFmpeg 解码器全覆盖（300+ 种）
- **多语言界面**：简体中文、繁體中文、English、日本語、한국어、Français
  标题栏右侧有语言按钮，也可以在菜单「语言 / Language」里切换
- **预设**：内置 6 套常用预设（微信分享 720p、高画质归档、只要音频、表情包 GIF、网页视频 WebM、播客 M4A），可把当前设置保存为自定义预设
- **Finder 集成**：右键 → 服务 →「用万能转码转换」；也可以「打开方式」或把文件拖到 Dock 图标
- **拖拽 / 选择文件 / 选择文件夹**（文件夹递归扫描，跳过隐藏目录与 .app 包）
- **批量队列**：进度百分比、实时倍速、逐个转换、随时取消、失败可重试
- **画质三档**：高质量 / 标准 / 小体积
- **分辨率**：保持原始、4K、1080p、720p、480p、360p，以及**自定义宽 × 高**
- **Apple 硬件加速**：VideoToolbox H.264 编码，失败自动回退软件编码
- **输出位置**：与源文件同目录，或指定文件夹；同名文件自动加序号，绝不覆盖
- 元数据保留、MP4/MOV faststart、GIF 两段式调色板优化

## 支持的语言

| 语言 | 代码 | 界面 |
| --- | --- | --- |
| 简体中文 | zh-Hans | 默认（系统语言为中文时自动选中） |
| 繁體中文 | zh-Hant | 系统语言为 zh-TW / zh-HK / zh-MO 时自动选中 |
| English | en | 系统语言为其他语言时回退 |
| 日本語 | ja | 系统语言为日语时自动选中 |
| 한국어 | ko | 系统语言为韩语时自动选中 |
| Français | fr | 系统语言为法语时自动选中 |

切换方式：菜单栏 **万能转码 → 语言**（Language），选完按提示重启即可。也支持环境变量 `ANYCONVERT_LANG=en` 强制指定。

## 输出格式

| 类型 | 格式 | 编码 |
| --- | --- | --- |
| 视频 | MP4 / MOV / M4V | H.264 + AAC |
| 视频 | MKV | H.264 + AAC |
| 视频 | WebM | VP9 + Opus |
| 视频 | AVI | MPEG-4 + MP3 |
| 视频 | WMV | WMV2 + WMA |
| 视频 | FLV / TS | H.264 + AAC |
| 视频 | MPG | MPEG-2 + MP2 |
| 视频 | 3GP | H.264(baseline) + AAC |
| 视频 | OGV | Theora + Vorbis |
| 视频 | GIF | 动图（无声音，自动调色板） |
| 音频 | MP3 / M4A / AAC / WMA / AC3 / OPUS / OGG | 有损，可选码率 128/192/256/320 kbps |
| 音频 | WAV / FLAC / ALAC / AIFF / CAF | 无损 / PCM |
| 图片 | JPG | 有损照片，画质三档对应 q 2/4/8 |
| 图片 | PNG | 无损，保留透明通道 |
| 图片 | WebP | 有损/透明，quality 92/82/68 |
| 图片 | AVIF | libaom AV1 静态图，CRF 20/28/36 |
| 图片 | TIFF | 无损，deflate 压缩 |
| 图片 | BMP | 无压缩位图 |
| 图片 | ICO | Windows 图标，自动缩放到 256px 内 |

输入支持 FFmpeg 能解码的一切：MP4、MKV、MOV、AVI、WMV、FLV、WebM、TS、M2TS、MPG、VOB、3GP、OGV、RMVB、ASF、MXF、M4A、FLAC、WAV、APE、WV、AIFF、OPUS、AMR，以及 JPG、PNG、WebP、AVIF、TIFF、BMP、ICO、HEIC 等。

## 图片转换说明

- 图片 → 图片：保留比例，可用「分辨率 / 自定义宽高」缩放，透明通道在 PNG / WebP / TIFF 间保留。
- 视频 → 图片：**截取第一帧**（例如 MP4 → JPG 生成封面图）。
- 图片 → 视频：出于格式语义，仅允许输出 GIF（单帧动图）；其他视频格式会提示「图片只能转换为图片格式或 GIF」。

## 下载（v1.5.0）

| 平台 | 文件 | 说明 |
| --- | --- | --- |
| macOS（推荐，Web UI） | [AnyConvert-1.5.0-macOS-web.zip](https://github.com/Inkpaper-mz/AnyConvert/releases/download/v1.5.0/AnyConvert-1.5.0-macOS-web.zip) | 解压双击 .app，首次运行安装脚本 |
| Windows | [AnyConvert-1.5.0-Windows-x64-Setup.exe](https://github.com/Inkpaper-mz/AnyConvert/releases/download/v1.5.0/AnyConvert-1.5.0-Windows-x64-Setup.exe) | **exe 安装包**，内置 Python 运行时与 FFmpeg |
| Linux | [AnyConvert-1.5.0-Linux-x64.tar.gz](https://github.com/Inkpaper-mz/AnyConvert/releases/download/v1.5.0/AnyConvert-1.5.0-Linux-x64.tar.gz) | Python 3.10+，`bash install.sh` |
| macOS 原生版（可选） | [AnyConvert-1.5.0-macOS-universal.dmg](https://github.com/Inkpaper-mz/AnyConvert/releases/download/v1.5.0/AnyConvert-1.5.0-macOS-universal.dmg) | 32 种音视频/图片格式，无文档与 PDF 工具 |

发布页：<https://github.com/Inkpaper-mz/AnyConvert/releases/tag/v1.5.0>

## 安装

### macOS（Web UI，推荐）

1. 解压 `AnyConvert-1.5.0-macOS-web.zip`；
2. 双击包内 **安装依赖.command**（首次，安装 PyMuPDF 并下载 LibreOffice）；
3. 双击 **万能转码.app**，浏览器自动打开本地界面；
4. 首次被系统拦截时：右键 .app → 打开。

### Windows

1. 双击 `AnyConvert-1.5.0-Windows-x64-Setup.exe`，按向导安装；
2. 从开始菜单 / 桌面启动「万能转码」；
3. 文档转换需另装 LibreOffice；PDF / 图片 / 音视频开箱即用。

### Linux

1. 解压 `AnyConvert-1.5.0-Linux-x64.tar.gz`；
2. 安装 Python 3.10+，执行 `bash install.sh`；
3. `bash 启动-Linux.sh` 启动。

### macOS 原生版（可选）

打开 DMG 把 **万能转码.app** 拖进「应用程序」。仅覆盖音视频与图片转换。

## 使用

1. 把文件拖进窗口（或点「选择文件 / 选择文件夹」）；
2. 右侧选择输出格式，例如 `.mp4` → `MP3`、`.png` → `JPG`；
3. 点「开始转换」，完成后点每行的「完成」徽章可在 Finder 中定位文件。

快捷键：`⌘O` 添加文件 · `⇧⌘O` 添加文件夹 · `⌘↩` 开始转换 · `⌘.` 取消 · `⇧⌘R` 打开输出文件夹

### 预设

![预设](docs/screenshot.png)

- 「预设」下拉里直接选内置组合，一步套用格式/画质/分辨率/码率
- 「保存为预设…」把当前设置存成自定义预设，可随时删除
- 预设会同时写入「按源格式记忆」的目标格式

### Finder 右键

- 在 Finder 选中文件 → 右键 → **服务** →「用万能转码转换 (AnyConvert)」
- 或右键 → **打开方式** → 万能转码
- 或把文件拖到 Dock 上的应用图标

### 自定义分辨率

![自定义分辨率](docs/custom-resolution.png)

分辨率选择「自定义…」后：

- 只填**宽** → 按宽度等比缩放（高度自动，保证偶数像素）
- 只填**高** → 按高度等比缩放（例如填 `720` 得到 720p）
- 两个都填 → **等比适配**进该尺寸框内，不拉伸变形
- 留空 → 不缩放

## 项目结构

```
AnyConvert/
├── Package.swift                    # SwiftPM 工程（macOS 13+，无第三方依赖）
├── Sources/AnyConvert/
│   ├── main.swift                   # 入口（含 --selftest / --print-env）
│   ├── L10n.swift                   # 6 语言本地化
│   ├── App/AppDelegate.swift        # 窗口、菜单、语言切换
│   ├── AppModel.swift               # 队列、设置、持久化、转换调度
│   ├── Models.swift                 # 格式目录（32 种）、画质、分辨率、任务模型
│   ├── CommandBuilder.swift         # 设置 → FFmpeg 参数的纯函数
│   ├── Engine.swift                 # 进程执行、进度解析、取消
│   ├── MediaProbe.swift             # ffprobe 解析时长/分辨率/轨道/图片判定
│   ├── Toolchain.swift              # 定位内置/系统 FFmpeg
│   ├── FileUtilities.swift          # 目录展开、输出命名
│   └── UI/                          # AppKit 界面（自定义绘制）
├── Resources/
│   ├── Info.plist
│   ├── Strings.json                 # 6 语言字符串表
│   └── *.lproj/                     # 本地化的 App 名称
├── scripts/build.sh                 # 打包 .app（图标、内置引擎、签名）
├── scripts/fetch_ffmpeg.sh          # 下载静态 FFmpeg
├── scripts/make_icon.swift          # 用 CoreGraphics 生成 .icns
└── vendor/                          # 静态 FFmpeg 二进制（arm64 / intel）
```

引擎查找顺序：`App/Contents/Resources/bin/ffmpeg-<arch>` → `$ANYCONVERT_BIN` → 工程 `vendor/` → `/opt/homebrew/bin` → `/usr/local/bin` → `PATH`。

## 自行构建

需要 macOS 13+ 与 Xcode Command Line Tools（Swift 5.9+）。

```bash
# 1. 下载内置转码引擎（arm64；WITH_INTEL=1 同时下载 Intel 版）
./scripts/fetch_ffmpeg.sh

# 2. 构建（默认当前架构，约 127 MB）
./scripts/build.sh

# 3. 通用二进制（Intel + Apple 芯片，约 309 MB）
ARCHS="arm64 x86_64" ./scripts/build.sh

# 4. 顺带产出 DMG
DMG=1 ./scripts/build.sh
```

> 国内网络下载较慢时可加代理：`PROXY=http://127.0.0.1:7890 ./scripts/fetch_ffmpeg.sh`

自检（32 种格式 + 7 项图片互转，全部 ffprobe 校验）：

```bash
swift build -c release
./.build/release/AnyConvert --selftest
```

## 许可

- 本项目的界面与业务代码：**MIT License**（见 `LICENSE`）
- 转码引擎：**FFmpeg**（GPL v3），静态构建来自 <https://ffmpeg.martin-riedl.de/>
  重新分发 App 时请遵守 GPL v3 的相应义务（提供源码获取方式与许可声明）。
- 图标由 `scripts/make_icon.swift` 生成，随项目一同按 MIT 授权。
