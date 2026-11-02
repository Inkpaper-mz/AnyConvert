# 架构说明 · AnyConvert

本文说明「万能转码」的分层、数据流与扩展点，以及设计上参考过的开源项目。

## 分层

```
┌──────────────────────────────────────────────┐
│ AppKit UI 层                                  │
│  RootView / JobRowView / SettingsPanel /      │
│  DropZoneView / Design（自绘控件）             │
└───────────────┬──────────────────────────────┘
                │ AppModelObserver（事件回调）
┌───────────────▼──────────────────────────────┐
│ AppModel（队列、设置、持久化、调度）            │
│  · 任务状态机 waiting→probing→running→done    │
│  · 能力筛选 availableFormats / ensureValidFormat│
│  · 按源扩展名记忆目标格式 ac.target.<ext>       │
│  · 批次快照：开始转换时冻结设置                  │
└───────────────┬──────────────────────────────┘
                │ ConversionEngine 协议
┌───────────────▼──────────────────────────────┐
│ 引擎层                                        │
│  FFmpegEngine（当前唯一实现）                  │
│    └ CommandBuilder：设置 → 参数（纯函数）      │
│  EngineRegistry：按输出格式挑选引擎             │
└───────────────┬──────────────────────────────┘
                │ Process + 管道
┌───────────────▼──────────────────────────────┐
│ 运行时基础                                    │
│  Engine（进程、-progress 解析、取消）           │
│  MediaProbe（ffprobe JSON → MediaInfo）        │
│  Toolchain（内置/系统 FFmpeg 定位）             │
│  FileUtilities（目录展开、输出命名）             │
└──────────────────────────────────────────────┘
```

UI 与模型之间只有 `AppModelObserver` 一个协议，模型不认识任何视图类型；这是后续接 CLI / 跨平台前端的基础。

## 数据流

1. **加入文件**：拖拽 / 选择 / 文件夹 / Finder 服务 / 打开方式 → `FileUtilities.expand` → 去重 → `AppModel.addFiles`
2. **探测**：后台 `ffprobe` → `MediaInfo`（时长、分辨率、音视频轨、是否图片）
3. **能力筛选**：`availableFormats` 根据当前任务集合求交集
   - 音频输出要求有音轨
   - 视频输出要求有视频轨，且图片输入只能输出 GIF
   - 图片输出要求有视频轨（视频可截首帧）
   - 当前格式失效时 `ensureValidFormat()` 自动切到同类可用格式
4. **入队**：串行 worker，开始前冻结 `ConversionSettings` 快照
5. **转换**：`EngineRegistry.engine(for:)` → 参数 → `Engine.run`（`-progress pipe:1` → 百分比/倍速/耗时）
6. **完成**：校验输出非空 → 记录输出路径、冻结耗时 → UI 可定位文件

## 预设系统（借鉴 File Converter）

```swift
struct ConversionPreset {
    var id, nameKey/name
    var formatID, quality, resolution, bitrate, hardware
    var customWidth/Height, extraArguments
}
```

- 内置 6 个：微信分享 720p、高画质归档、只要音频、表情包 GIF、网页视频 WebM、播客 M4A
- 自定义预设存 `UserDefaults["ac.presets"]`（JSON），可保存当前设置、可删除
- 应用预设会一次性写入格式/画质/分辨率/码率/硬件/自定义尺寸/附加参数

## 引擎扩展点

新增引擎（如 LibreOffice、Pandoc、ImageMagick）只需：

1. 实现 `ConversionEngine`：`handles(_:)` 决定负责哪些输出格式，`arguments(...)` 返回命令行参数
2. 注册进 `EngineRegistry.engines`
3. 在 `Catalog` 增加对应输出格式（必要时新增 `MediaKind`）

`AppModel` 不关心具体引擎，失败回退、进度解析、取消都复用 `Engine`。

## 本地化

- `L10n` 从 `Resources/Strings.json` 读取 6 种语言（zh-Hans / zh-Hant / en / ja / ko / fr）
- 语言选择存 `UserDefaults["ac.language"]`，菜单切换后重启生效
- 内置预设名、格式说明、错误提示都走 key
- `Info.plist` 声明 `CFBundleLocalizations`，`*.lproj/InfoPlist.strings` 提供本地化 App 名

## Finder 集成

- **Services**：`NSServices` 声明 `convertWithAnyConvert`，`NSApp.servicesProvider` 注册，右键 → 服务 →「用万能转码转换」
- **打开方式**：`CFBundleDocumentTypes` 注册 `public.movie/audio/image`，Finder 双击或右键「打开方式」直接入队
- **Dock**：把文件拖到 Dock 图标，走 `application(_:openFiles:)`

## 借鉴来源与许可

| 项目 | 借鉴内容 | 许可 |
| --- | --- | --- |
| [Tichau/FileConverter](https://github.com/Tichau/FileConverter) | 预设模型、任务按格式分派（JobFactory 思想）、输出后处理、右键入口的产品形态 | GPLv3：仅借鉴思想，未复制代码 |
| [LaoFeng-mouse/flyingmouse-format](https://github.com/LaoFeng-mouse/flyingmouse-format) | capabilities/targets 能力筛选、按源格式记忆目标、阶段进度与耗时冻结、批次快照、资源边界意识 | 非商用许可：仅借鉴思想，未复制代码 |
| FFmpeg | 转码引擎（静态构建） | GPLv3 |

## 路线图

- **P0**：预设、Finder 服务、能力筛选（已完成）
- **P1**：CLI（`--cli` + `--json`，便于自动化与跨平台复用）、转换后动作（打开目录/移到废纸篓）
- **P1**：更多引擎（LibreOffice 文档、Pandoc Markdown）接入 `EngineRegistry`
- **P2**：Windows/Linux 前端（复用 `AppModel` 的规则与 `CommandBuilder` 逻辑）
