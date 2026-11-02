import Foundation

// MARK: - 输出格式

enum MediaKind: String, Codable {
    case video
    case audio
    case image
}

struct OutputFormat: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitleKey: String
    let ext: String
    let kind: MediaKind
    let lossless: Bool

    var subtitle: String { L10n.t(subtitleKey) }
    var menuLabel: String { "\(title)  ·  \(subtitle)" }
    var isAnimatedImage: Bool { id == "gif" }
    var isImage: Bool { kind == .image }
}

enum Catalog {
    static let videoFormats: [OutputFormat] = [
        .init(id: "mp4",  title: "MP4",   subtitleKey: "fmt.mp4.sub",  ext: "mp4",  kind: .video, lossless: false),
        .init(id: "mov",  title: "MOV",   subtitleKey: "fmt.mov.sub",  ext: "mov",  kind: .video, lossless: false),
        .init(id: "m4v",  title: "M4V",   subtitleKey: "fmt.m4v.sub",  ext: "m4v",  kind: .video, lossless: false),
        .init(id: "mkv",  title: "MKV",   subtitleKey: "fmt.mkv.sub",  ext: "mkv",  kind: .video, lossless: false),
        .init(id: "webm", title: "WebM",  subtitleKey: "fmt.webm.sub", ext: "webm", kind: .video, lossless: false),
        .init(id: "avi",  title: "AVI",   subtitleKey: "fmt.avi.sub",  ext: "avi",  kind: .video, lossless: false),
        .init(id: "wmv",  title: "WMV",   subtitleKey: "fmt.wmv.sub",  ext: "wmv",  kind: .video, lossless: false),
        .init(id: "flv",  title: "FLV",   subtitleKey: "fmt.flv.sub",  ext: "flv",  kind: .video, lossless: false),
        .init(id: "ts",   title: "TS",    subtitleKey: "fmt.ts.sub",   ext: "ts",   kind: .video, lossless: false),
        .init(id: "mpg",  title: "MPG",   subtitleKey: "fmt.mpg.sub",  ext: "mpg",  kind: .video, lossless: false),
        .init(id: "3gp",  title: "3GP",   subtitleKey: "fmt.3gp.sub",  ext: "3gp",  kind: .video, lossless: false),
        .init(id: "ogv",  title: "OGV",   subtitleKey: "fmt.ogv.sub",  ext: "ogv",  kind: .video, lossless: false),
        .init(id: "gif",  title: "GIF",   subtitleKey: "fmt.gif.sub",  ext: "gif",  kind: .video, lossless: false),
    ]

    static let audioFormats: [OutputFormat] = [
        .init(id: "mp3",  title: "MP3",  subtitleKey: "fmt.mp3.sub",  ext: "mp3",  kind: .audio, lossless: false),
        .init(id: "m4a",  title: "M4A",  subtitleKey: "fmt.m4a.sub",  ext: "m4a",  kind: .audio, lossless: false),
        .init(id: "aac",  title: "AAC",  subtitleKey: "fmt.aac.sub",  ext: "aac",  kind: .audio, lossless: false),
        .init(id: "wav",  title: "WAV",  subtitleKey: "fmt.wav.sub",  ext: "wav",  kind: .audio, lossless: true),
        .init(id: "flac", title: "FLAC", subtitleKey: "fmt.flac.sub", ext: "flac", kind: .audio, lossless: true),
        .init(id: "alac", title: "ALAC", subtitleKey: "fmt.alac.sub", ext: "m4a",  kind: .audio, lossless: true),
        .init(id: "ogg",  title: "OGG",  subtitleKey: "fmt.ogg.sub",  ext: "ogg",  kind: .audio, lossless: false),
        .init(id: "opus", title: "OPUS", subtitleKey: "fmt.opus.sub", ext: "opus", kind: .audio, lossless: false),
        .init(id: "wma",  title: "WMA",  subtitleKey: "fmt.wma.sub",  ext: "wma",  kind: .audio, lossless: false),
        .init(id: "aiff", title: "AIFF", subtitleKey: "fmt.aiff.sub", ext: "aiff", kind: .audio, lossless: true),
        .init(id: "ac3",  title: "AC3",  subtitleKey: "fmt.ac3.sub",  ext: "ac3",  kind: .audio, lossless: false),
        .init(id: "caf",  title: "CAF",  subtitleKey: "fmt.caf.sub",  ext: "caf",  kind: .audio, lossless: false),
    ]

    static let imageFormats: [OutputFormat] = [
        .init(id: "jpg",  title: "JPG",  subtitleKey: "fmt.jpg.sub",  ext: "jpg",  kind: .image, lossless: false),
        .init(id: "png",  title: "PNG",  subtitleKey: "fmt.png.sub",  ext: "png",  kind: .image, lossless: true),
        .init(id: "webp", title: "WebP", subtitleKey: "fmt.webp.sub", ext: "webp", kind: .image, lossless: false),
        .init(id: "avif", title: "AVIF", subtitleKey: "fmt.avif.sub", ext: "avif", kind: .image, lossless: false),
        .init(id: "tiff", title: "TIFF", subtitleKey: "fmt.tiff.sub", ext: "tiff", kind: .image, lossless: true),
        .init(id: "bmp",  title: "BMP",  subtitleKey: "fmt.bmp.sub",  ext: "bmp",  kind: .image, lossless: true),
        .init(id: "ico",  title: "ICO",  subtitleKey: "fmt.ico.sub",  ext: "ico",  kind: .image, lossless: true),
    ]

    static let all: [OutputFormat] = videoFormats + audioFormats + imageFormats

    static func format(_ id: String) -> OutputFormat {
        all.first { $0.id == id } ?? videoFormats[0]
    }

    static func formats(for kind: MediaKind) -> [OutputFormat] {
        switch kind {
        case .video: return videoFormats
        case .audio: return audioFormats
        case .image: return imageFormats
        }
    }
}

// MARK: - 画质 / 分辨率 / 码率

enum Quality: String, CaseIterable, Identifiable, Codable {
    case high, balanced, small

    var id: String { rawValue }

    var title: String { L10n.t("quality.\(rawValue)") }
    var detail: String { L10n.t("quality.\(rawValue).detail") }

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

    // 图片编码参数
    var jpegQuality: Int {
        switch self { case .high: return 2; case .balanced: return 4; case .small: return 8 }
    }
    var pngLevel: Int {
        switch self { case .high: return 9; case .balanced: return 6; case .small: return 3 }
    }
    var webpQuality: Int {
        switch self { case .high: return 92; case .balanced: return 82; case .small: return 68 }
    }
    var avifCRF: Int {
        switch self { case .high: return 20; case .balanced: return 28; case .small: return 36 }
    }
}

enum ResolutionPreset: String, CaseIterable, Identifiable, Codable {
    case original, uhd4k, fhd1080, hd720, sd480, sd360, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return L10n.t("res.original")
        case .uhd4k: return L10n.t("res.4k")
        case .fhd1080: return L10n.t("res.1080")
        case .hd720: return L10n.t("res.720")
        case .sd480: return L10n.t("res.480")
        case .sd360: return L10n.t("res.360")
        case .custom: return L10n.t("res.custom")
        }
    }

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
    var isImage: Bool = false
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
            case .waiting: return L10n.t("status.waiting")
            case .probing: return L10n.t("status.probing")
            case .running: return L10n.t("status.running")
            case .done: return L10n.t("status.done")
            case .failed: return L10n.t("status.failed")
            case .cancelled: return L10n.t("status.cancelled")
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
    var startedAt: Date?
    var elapsed: TimeInterval = 0

    var displayName: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.uppercased() }

    var fileSize: String {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.int64Value ?? 0
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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
    var extraArguments: [String] = []
    var targetBytes: Int64? = nil
    var allowDownscale: Bool = true
}

enum ConvertError: LocalizedError {
    case toolchainMissing
    case probeFailed(String)
    case noAudioTrack
    case noVideoTrack
    case imageNeedsImageFormat
    case encodeFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .toolchainMissing:
            return L10n.t("msg.noEngine")
        case .probeFailed(let detail):
            return L10n.t("msg.probeFail", detail)
        case .noAudioTrack:
            return L10n.t("msg.noAudio")
        case .noVideoTrack:
            return L10n.t("msg.noVideo")
        case .imageNeedsImageFormat:
            return L10n.t("msg.imageOnly")
        case .encodeFailed(let detail):
            return detail
        case .cancelled:
            return L10n.t("msg.cancelled")
        }
    }
}
