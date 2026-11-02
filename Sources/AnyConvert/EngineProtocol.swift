import Foundation

/// 转换引擎抽象：目前只有 FFmpeg，后续可接入 LibreOffice / ImageMagick 等
protocol ConversionEngine {
    var id: String { get }
    var displayName: String { get }
    /// 该引擎是否负责这种输出格式
    func handles(_ format: OutputFormat) -> Bool
    /// 生成完整参数；返回 nil 表示无法处理
    func arguments(for settings: ConversionSettings,
                   input: URL,
                   output: URL,
                   info: MediaInfo) -> [String]?
}

struct FFmpegEngine: ConversionEngine {
    let id = "ffmpeg"
    let displayName = "FFmpeg"

    func handles(_ format: OutputFormat) -> Bool { true }

    func arguments(for settings: ConversionSettings,
                   input: URL,
                   output: URL,
                   info: MediaInfo) -> [String]? {
        CommandBuilder.arguments(settings: settings, input: input, output: output, info: info)
    }
}

/// 引擎注册表：按输出格式挑选引擎（对应 File Converter 的 ConversionJobFactory）
enum EngineRegistry {
    static let engines: [ConversionEngine] = [FFmpegEngine()]

    static func engine(for format: OutputFormat) -> ConversionEngine? {
        engines.first { $0.handles(format) }
    }
}
