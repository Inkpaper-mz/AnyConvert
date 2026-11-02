import Foundation

// MARK: - 输出格式

enum MediaKind: String, Codable {
    case video
    case audio
}

struct OutputFormat: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let ext: String
    let kind: MediaKind
    let lossless: Bool
    /// 该格式是否真的带视频轨（GIF 特殊处理）
    var isAnimatedImage: Bool { id == "gif" }

    var menuLabel: String { "\(title)  ·  \(subtitle)" }
}

enum Catalog {
    static let videoFormats: [OutputFormat] = [
        .init(id: "mp4",  title: "MP4",   subtitle: "H.264 + AAC · 最通用", ext: "mp4",  kind: .video, lossless: false),
        .init(id: "mov",  title: "MOV",   subtitle: "H.264 + AAC · 苹果",   ext: "mov",  kind: .video, lossless: false),
        .init(id: "m4v",  title: "M4V",   subtitle: "H.264 + AAC · iTunes", ext: "m4v",  kind: .video, lossless: false),
        .init(id: "mkv",  title: "MKV",   subtitle: "H.264 + AAC · 高兼容", ext: "mkv",  kind: .video, lossless: false),
        .init(id: "webm", title: "WebM",  subtitle: "VP9 + Opus · 网页",    ext: "webm", kind: .video, lossless: false),
        .init(id: "avi",  title: "AVI",   subtitle: "MPEG-4 + MP3 · 老设备", ext: "avi", kind: .video, lossless: false),
        .init(id: "wmv",  title: "WMV",   subtitle: "WMV2 + WMA · Windows",  ext: "wmv",  kind: .video, lossless: false),
        .init(id: "flv",  title: "FLV",   subtitle: "H.264 + AAC · 旧网页",  ext: "flv",  kind: .video, lossless: false),
        .init(id: "ts",   title: "TS",    subtitle: "H.264 + AAC · 电视",    ext: "ts",   kind: .video, lossless: false),
        .init(id: "mpg",  title: "MPG",   subtitle: "MPEG-2 + MP2 · 老播放器", ext: "mpg", kind: .video, lossless: false),
        .init(id: "3gp",  title: "3GP",   subtitle: "H.264 + AAC · 手机",    ext: "3gp",  kind: .video, lossless: false),
        .init(id: "ogv",  title: "OGV",   subtitle: "Theora + Vorbis · 开源", ext: "ogv", kind: .video, lossless: false),
        .init(id: "gif",  title: "GIF",   subtitle: "动图 · 无声音",          ext: "gif",  kind: .video, lossless: false),
    ]

    static let audioFormats: [OutputFormat] = [
        .init(id: "mp3",  title: "MP3",  subtitle: "最通用的音频",   ext: "mp3",  kind: .audio, lossless: false),
        .init(id: "m4a",  title: "M4A",  subtitle: "AAC · 苹果设备", ext: "m4a",  kind: .audio, lossless: false),
        .init(id: "aac",  title: "AAC",  subtitle: "裸流 ADTS",      ext: "aac",  kind: .audio, lossless: false),
        .init(id: "wav",  title: "WAV",  subtitle: "PCM 无损",       ext: "wav",  kind: .audio, lossless: true),
        .init(id: "flac", title: "FLAC", subtitle: "无损压缩",       ext: "flac", kind: .audio, lossless: true),
        .init(id: "alac", title: "ALAC", subtitle: "苹果无损",       ext: "m4a",  kind: .audio, lossless: true),
        .init(id: "ogg",  title: "OGG",  subtitle: "Vorbis",         ext: "ogg",  kind: .audio, lossless: false),
        .init(id: "opus", title: "OPUS", subtitle: "高效压缩",       ext: "opus", kind: .audio, lossless: false),
        .init(id: "wma",  title: "WMA",  subtitle: "Windows 音频",   ext: "wma",  kind: .audio, lossless: false),
        .init(id: "aiff", title: "AIFF", subtitle: "PCM 无损",       ext: "aiff", kind: .audio, lossless: true),
        .init(id: "ac3",  title: "AC3",  subtitle: "杜比数字",       ext: "ac3",  kind: .audio, lossless: false),
        .init(id: "caf",  title: "CAF",  subtitle: "苹果音频容器",   ext: "caf",  kind: .audio, lossless: false),
    ]

    static let all: [OutputFormat] = videoFormats + audioFormats

    static func format(_ id: String) -> OutputFormat {
        all.first { $0.id == id } ?? videoFormats[0]
    }
}

// MARK: - 画质 / 分辨率 / 码率

enum Quality: String, CaseIterable, Identifiable, Codable {
    case high, balanced, small

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: return "高质量"
        case .balanced: return "标准"
        case .small: return "小体积"
        }
    }

    var detail: String {
        switch self {
        case .high: return "接近原片，文件较大"
        case .balanced: return "画质与体积均衡"
        case .small: return "适合分享与传输"
        }
    }

    var x264CRF: Int {
        switch self { case .high: return 18; case .balanced: return 23; case .small: return 28 }
    }

    var x265CRF: Int {
        switch self { case .high: return 22; case .balanced: return 27; case .small: return 32 }
    }

    var vp9CRF: Int {
        switch self { case .high: return 24; case .balanced: return 32; case .small: return 40 }
    }

    var theoraQuality: Int {
        switch self { case .high: return 8; case .balanced: return 6; case .small: return 4 }
    }

    var mpegQuality: Int {
        switch self { case .high: return 2; case .balanced: return 4; case .small: return 8 }
    }

    var hardwareBitrate: String {
        switch self { case .high: return "12M"; case .balanced: return "6M"; case .small: return "3M" }
    }
}

enum ResolutionPreset: String, CaseIterable, Identifiable, Codable {
    case original, uhd4k, fhd1080, hd720, sd480, sd360, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "保持原始"
        case .uhd4k: return "4K"
        case .fhd1080: return "1080p"
        case .hd720: return "720p"
        case .sd480: return "480p"
        case .sd360: return "360p"
        case .custom: return "自定义…"
        }
    }

    /// 目标高度；nil 表示不缩放
    var height: Int? {
        switch self {
        case .original: return nil
        case .uhd4k: return 2160
        case .fhd1080: return 1080
        case .hd720: return 720
        case .sd480: return 480
        case .sd360: return 360
        case .custom: return nil
        }
    }
}

enum AudioBitrate: String, CaseIterable, Identifiable, Codable {
    case b320, b256, b192, b128

    var id: String { rawValue }
    var title: String {
        switch self { case .b320: return "320 kbps"; case .b256: return "256 kbps"; case .b192: return "192 kbps"; case .b128: return "128 kbps" }
    }
    var value: String {
        switch self { case .b320: return "320k"; case .b256: return "256k"; case .b192: return "192k"; case .b128: return "128k" }
    }
}

enum OutputMode: String, Codable {
    case alongside
    case custom
}

// MARK: - 媒体信息

struct MediaInfo: Codable, Equatable {
    var duration: Double = 0
    var width: Int = 0
    var height: Int = 0
    var hasVideo: Bool = false
    var hasAudio: Bool = false
    var videoCodec: String = ""
    var audioCodec: String = ""
    var container: String = ""

    var resolutionText: String {
        guard width > 0, height > 0 else { return "—" }
        return "\(width)×\(height)"
    }
}

// MARK: - 任务

struct Job: Identifiable {
    enum Status: Equatable {
        case waiting
        case probing
        case running
        case done
        case failed
        case cancelled

        var label: String {
            switch self {
            case .waiting: return "等待"
            case .probing: return "分析中"
            case .running: return "转换中"
            case .done: return "完成"
            case .failed: return "失败"
            case .cancelled: return "已取消"
            }
        }
    }

    let id = UUID()
    let url: URL
    var info: MediaInfo?
    var status: Status = .waiting
    var progress: Double = 0
    var speed: String = ""
    var message: String = ""
    var outputURL: URL?

    var displayName: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.uppercased() }

    var fileSize: String {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.int64Value ?? 0
        guard bytes > 0 else { return "—" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    var durationText: String {
        guard let d = info?.duration, d > 0 else { return "—" }
        return Job.timecode(d)
    }

    static func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - 转换参数

struct ConversionSettings {
    var format: OutputFormat
    var quality: Quality
    var resolution: ResolutionPreset
    var audioBitrate: AudioBitrate
    var hardware: Bool
    var customWidth: Int? = nil
    var customHeight: Int? = nil
}

enum ConvertError: LocalizedError {
    case toolchainMissing
    case probeFailed(String)
    case noAudioTrack
    case noVideoTrack
    case encodeFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .toolchainMissing:
            return "找不到 FFmpeg 引擎，请重新安装本应用。"
        case .probeFailed(let detail):
            return "无法识别的媒体文件：\(detail)"
        case .noAudioTrack:
            return "该文件没有音频轨，无法转换为音频。"
        case .noVideoTrack:
            return "该文件没有视频轨，无法转换为视频。"
        case .encodeFailed(let detail):
            return detail
        case .cancelled:
            return "已取消"
        }
    }
}
