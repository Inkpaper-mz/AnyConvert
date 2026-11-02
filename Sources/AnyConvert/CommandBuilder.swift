import Foundation

/// 把「目标格式 + 画质设置 + 源信息」翻译成 FFmpeg 参数。
enum CommandBuilder {
    static func arguments(settings: ConversionSettings,
                          input: URL,
                          output: URL,
                          info: MediaInfo) -> [String] {
        let fmt = settings.format
        let quality = settings.quality

        var args: [String] = [
            "-hide_banner", "-nostdin",
            "-loglevel", "error",
            "-progress", "pipe:1",
            "-y",
            "-i", input.path,
        ]

        if fmt.isAnimatedImage {
            args += gifArguments(settings: settings, info: info, output: output)
            return args
        }

        if fmt.kind == .video {
            guard info.hasVideo else { return args }
            args += ["-map", "0:v:0?", "-map", "0:a:0?"]
            args += videoArguments(settings: settings, info: info)
        } else {
            guard info.hasAudio else { return args }
            args += ["-map", "0:a:0?", "-vn"]
            args += audioArguments(settings: settings)
        }

        args += ["-map_metadata", "0"]

        switch fmt.id {
        case "mp4", "mov", "m4v", "alac", "m4a":
            args += ["-movflags", "+faststart"]
        case "3gp":
            args += ["-f", "3gp"]
        case "ts":
            args += ["-f", "mpegts"]
        case "avi":
            args += ["-f", "avi"]
        case "flv":
            args += ["-f", "flv"]
        case "wmv":
            args += ["-f", "asf"]
        default:
            break
        }

        args.append(output.path)
        return args
    }

    // MARK: - 视频

    private static func videoArguments(settings: ConversionSettings, info: MediaInfo) -> [String] {
        var args: [String] = []
        if let filter = videoFilter(settings: settings, info: info) {
            args += ["-vf", filter]
        }

        let fmt = settings.format
        let q = settings.quality

        switch fmt.id {
        case "mp4", "mov", "m4v", "mkv", "flv", "ts", "3gp":
            if settings.hardware {
                args += ["-c:v", "h264_videotoolbox", "-b:v", q.hardwareBitrate, "-profile:v", "high"]
            } else {
                args += [
                    "-c:v", "libx264",
                    "-preset", x264Preset(q),
                    "-crf", "\(q.x264CRF)",
                    "-profile:v", fmt.id == "3gp" ? "baseline" : "high",
                    "-pix_fmt", "yuv420p",
                ]
            }
            args += ["-c:a", "aac", "-b:a", audioBitrate(for: fmt, settings: settings)]

        case "webm":
            args += [
                "-c:v", "libvpx-vp9",
                "-crf", "\(q.vp9CRF)",
                "-b:v", "0",
                "-row-mt", "1",
                "-deadline", "good",
                "-cpu-used", "2",
                "-pix_fmt", "yuv420p",
            ]
            args += ["-c:a", "libopus", "-b:a", settings.audioBitrate.value]

        case "avi":
            args += ["-c:v", "mpeg4", "-q:v", "\(q.mpegQuality)", "-pix_fmt", "yuv420p"]
            args += ["-c:a", "libmp3lame", "-b:a", settings.audioBitrate.value]

        case "wmv":
            args += ["-c:v", "wmv2", "-b:v", q.hardwareBitrate, "-pix_fmt", "yuv420p"]
            args += ["-c:a", "wmav2", "-b:a", settings.audioBitrate.value]

        case "mpg":
            args += ["-c:v", "mpeg2video", "-q:v", "\(q.mpegQuality)", "-pix_fmt", "yuv420p"]
            args += ["-c:a", "mp2", "-b:a", "192k"]

        case "ogv":
            args += ["-c:v", "libtheora", "-q:v", "\(q.theoraQuality)"]
            args += ["-c:a", "libvorbis", "-q:a", "5"]

        default:
            args += ["-c:v", "libx264", "-preset", x264Preset(q), "-crf", "\(q.x264CRF)", "-pix_fmt", "yuv420p"]
            args += ["-c:a", "aac", "-b:a", settings.audioBitrate.value]
        }

        return args
    }

    private static func x264Preset(_ q: Quality) -> String {
        switch q {
        case .high: return "slow"
        case .balanced: return "medium"
        case .small: return "faster"
        }
    }

    /// 缩放 / 偶数对齐滤镜；无需处理时返回 nil
    private static func videoFilter(settings: ConversionSettings, info: MediaInfo) -> String? {
        if settings.resolution == .custom {
            return customScale(settings: settings)
        }
        if let target = settings.resolution.height, info.height > target {
            return "scale=-2:\(target):flags=lanczos"
        }
        if info.height > 0, info.height % 2 != 0 {
            return "scale=trunc(iw/2)*2:trunc(ih/2)*2"
        }
        return nil
    }

    /// 自定义分辨率：只填一边则等比缩放；两边都填则等比适配到框内
    private static func customScale(settings: ConversionSettings) -> String? {
        let width = settings.customWidth.flatMap { $0 > 0 ? even($0) : nil }
        let height = settings.customHeight.flatMap { $0 > 0 ? even($0) : nil }
        switch (width, height) {
        case let (w?, h?):
            return "scale=\(w):\(h):force_original_aspect_ratio=decrease:flags=lanczos,"
                + "scale=trunc(iw/2)*2:trunc(ih/2)*2"
        case let (w?, nil):
            return "scale=\(w):-2:flags=lanczos"
        case let (nil, h?):
            return "scale=-2:\(h):flags=lanczos"
        default:
            return nil
        }
    }

    private static func even(_ value: Int) -> Int {
        let clamped = min(max(value, 16), 7680)
        return clamped % 2 == 0 ? clamped : clamped - 1
    }

    // MARK: - 音频

    private static func audioArguments(settings: ConversionSettings) -> [String] {
        let bitrate = settings.audioBitrate.value
        switch settings.format.id {
        case "mp3":  return ["-c:a", "libmp3lame", "-b:a", bitrate]
        case "m4a":  return ["-c:a", "aac", "-b:a", bitrate]
        case "aac":  return ["-c:a", "aac", "-b:a", bitrate]
        case "wav":  return ["-c:a", "pcm_s16le"]
        case "flac": return ["-c:a", "flac", "-compression_level", "5"]
        case "alac": return ["-c:a", "alac"]
        case "ogg":  return ["-c:a", "libvorbis", "-q:a", "5"]
        case "opus": return ["-c:a", "libopus", "-b:a", bitrate]
        case "wma":  return ["-c:a", "wmav2", "-b:a", bitrate]
        case "aiff": return ["-c:a", "pcm_s16be"]
        case "ac3":  return ["-c:a", "ac3", "-b:a", "384k"]
        case "caf":  return ["-c:a", "pcm_s16le"]
        default:     return ["-c:a", "aac", "-b:a", bitrate]
        }
    }

    private static func audioBitrate(for format: OutputFormat, settings: ConversionSettings) -> String {
        settings.audioBitrate.value
    }

    // MARK: - GIF 动图

    private static func gifArguments(settings: ConversionSettings, info: MediaInfo, output: URL) -> [String] {
        // 限制宽度，兼顾体积与清晰度
        var width = info.width > 0 ? info.width : 480
        switch settings.quality {
        case .high: width = min(width, 720)
        case .balanced: width = min(width, 540)
        case .small: width = min(width, 360)
        }
        if width % 2 != 0 { width -= 1 }
        if width < 80 { width = 80 }

        let fps = settings.quality == .high ? 15 : 12
        let filter = "fps=\(fps),scale=\(width):-2:flags=lanczos,"
            + "split[s0][s1];[s0]palettegen=max_colors=256:stats_mode=diff[p];"
            + "[s1][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle"

        return [
            "-map", "0:v:0",
            "-an",
            "-vf", filter,
            "-loop", "0",
            output.path,
        ]
    }
}
