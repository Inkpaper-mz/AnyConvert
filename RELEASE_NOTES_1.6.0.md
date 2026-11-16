# AnyConvert 1.6.0 更新说明（发布候选）

本次更新面向 macOS Apple 芯片版，需要 macOS 14 或更新版本。

- 修复 Word 转 PDF 时系统中文字体现示为空白或方框的问题。
- HTML 转 DOCX 改用 Pandoc，修复无法找到 DOCX 导出过滤器的问题。
- 增加 Markdown、Word 和 PDF 的基础转换，以及 CSV／JSON、表格型 Markdown／HTML 的部分转换。
- 图片和动图可转为 5 秒 MP4／WebM；MP4／MKV 增加 H.264、H.265、AV1 编码选择。
- 引入 libvips／librsvg SVG 渲染和 LibRaw 相机 RAW 解码；补充 PSD／EXR 识别。
- PDF 工具支持 PNG／JPG 页面导出；ZIP 可选择压缩级别并展示大小。
- 文件夹批量导入支持文档和媒体，混合类型不再因当前目标格式被静默丢弃。
- 修复命令行文档转换和目标格式查询；补充回归测试。

## 已知限制

PDF 转 Markdown 主要提取文字，无法保证还原复杂排版；复杂表格与嵌套 JSON 不支持无损互转。视频按目标大小压缩目前仅支持 H.264。RAW 输出使用相机白平衡和 8 位图片，不同相机尚未全面测试。图形界面的文件夹选择流程尚未完整自动化验证。

本项目使用和参考的第三方项目、许可证与来源详见 [THIRD_PARTY.md](THIRD_PARTY.md)。此文件为发布候选说明，不表示二进制分发合规检查已完成。
