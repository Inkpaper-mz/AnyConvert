import Foundation

/// 按目标体积压缩（图片 / 视频）
///
/// 图片：质量二分（JPEG qscale / WebP quality / AVIF CRF），允许降分辨率时逐级缩小再二分。
/// 视频：目标体积反推码率 + x264 两遍编码，超标按比例回退；允许降分辨率时按 bpp 阶梯降档。
enum CompressionEngine {

    enum Failure: LocalizedError {
        case unreachable(target: Int64, best: Int64)
        case formatUnsupported
        case pngNeedsDownscale
        case engine(String)

        var errorDescription: String? {
            switch self {
            case .unreachable(let target, let best):
                return L10n.t("msg.targetUnreachable", Self.mb(target), Self.mb(best))
            case .formatUnsupported:
                return L10n.t("msg.compressFormat")
            case .pngNeedsDownscale:
                return L10n.t("msg.pngNeedsScale")
            case .engine(let detail):
                return detail
            }
        }

        static func mb(_ bytes: Int64) -> String {
            String(format: "%.2f MB", Double(bytes) / 1024 / 1024)
        }
    }

    private static let imageTargets: Set<String> = ["jpg", "png", "webp", "avif", "tiff", "bmp", "ico"]

    // MARK: - 入口

    static func compress(input: URL,
                         settings: ConversionSettings,
                         output: URL,
                         info: MediaInfo,
                         progress: @escaping (Double, String) -> Void) async throws {
        guard let target = settings.targetBytes, target > 0 else { return }
        switch settings.format.kind {
        case .image:
            try await compressImage(input: input, settings: settings, output: output, target: target, info: info)
        case .video:
            try await compressVideo(input: input, settings: settings, output: output, target: target, info: info, progress: progress)
        default:
            throw Failure.formatUnsupported
        }
    }

    // MARK: - 图片

    private static func compressImage(input: URL,
                                      settings: ConversionSettings,
                                      output: URL,
                                      target: Int64,
                                      info: MediaInfo) async throws {
        let ext = settings.format.ext.lowercased()
        guard imageTargets.contains(ext) else { throw Failure.formatUnsupported }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("anyconvert-img-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        var bestSize: Int64 = 0

        if ext == "png" {
            guard settings.allowDownscale else { throw Failure.pngNeedsDownscale }
            var scale = 0.9
            while scale >= 0.15 {
                let path = try await encodeImage(input: input, ext: ext, quality: 0, scale: scale, work: work)
                let size = fileSize(path)
                bestSize = max(bestSize, size)
                if size <= target {
                    try replace(path, with: output)
                    return
                }
                scale *= 0.8
            }
            throw Failure.unreachable(target: target, best: bestSize)
        }

        if let quality = try await searchQuality(input: input, ext: ext, target: target, work: work) {
            let path = try await encodeImage(input: input, ext: ext, quality: quality, scale: 1.0, work: work)
            guard fileSize(path) <= target else {
                throw Failure.unreachable(target: target, best: fileSize(path))
            }
            try replace(path, with: output)
            return
        }

        guard settings.allowDownscale else {
            let path = try await encodeImage(input: input, ext: ext, quality: worstQuality(ext), scale: 1.0, work: work)
            bestSize = fileSize(path)
            throw Failure.unreachable(target: target, best: bestSize)
        }

        var scale = 0.8
        while scale >= 0.15 {
            if let quality = try await searchQuality(input: input, ext: ext, target: target, work: work, scale: scale) {
                let path = try await encodeImage(input: input, ext: ext, quality: quality, scale: scale, work: work)
                if fileSize(path) <= target {
                    try replace(path, with: output)
                    return
                }
            }
            let probe = try await encodeImage(input: input, ext: ext, quality: worstQuality(ext), scale: scale, work: work)
            bestSize = fileSize(probe)
            scale *= 0.75
        }
        throw Failure.unreachable(target: target, best: bestSize)
    }

    private static func worstQuality(_ ext: String) -> Int {
        switch ext {
        case "jpg", "jpeg": return 31
        case "webp": return 60
        case "avif": return 45
        default: return 31
        }
    }

    private static func searchQuality(input: URL, ext: String, target: Int64,
                                      work: URL, scale: Double = 1.0) async throws -> Int? {
        var lo = 2, hi = 31
        switch ext {
        case "jpg", "jpeg": lo = 2; hi = 31
        case "webp": lo = 5; hi = 95
        case "avif": lo = 10; hi = 55
        default: return nil
        }
        var best: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            let path = try await encodeImage(input: input, ext: ext, quality: mid, scale: scale, work: work)
            if fileSize(path) <= target {
                best = mid
                if ext == "avif" { hi = mid - 1 } else { lo = mid + 1 }
            } else {
                if ext == "avif" { lo = mid + 1 } else { hi = mid - 1 }
            }
        }
        return best
    }

    private static func encodeImage(input: URL, ext: String, quality: Int,
                                    scale: Double, work: URL) async throws -> URL {
        let path = work.appendingPathComponent("\(UUID().uuidString.prefix(8)).\(ext)")
        var args = ["-hide_banner", "-nostdin", "-y", "-i", input.path]
        if scale < 0.999 {
            args += ["-vf", String(format: "scale=iw*%.4f:ih*%.4f:flags=lanczos", scale, scale)]
        }
        switch ext {
        case "jpg", "jpeg": args += ["-c:v", "mjpeg", "-q:v", "\(quality)", "-pix_fmt", "yuvj420p"]
        case "webp": args += ["-c:v", "libwebp", "-quality", "\(quality)", "-pix_fmt", "yuva420p"]
        case "avif": args += ["-c:v", "libaom-av1", "-crf", "\(quality)", "-b:v", "0", "-still-picture", "1"]
        case "png": args += ["-c:v", "png", "-compression_level", "9"]
        case "tiff": args += ["-c:v", "tiff", "-pix_fmt", "rgba", "-compression_algo", "deflate"]
        case "bmp": args += ["-c:v", "bmp", "-pix_fmt", "bgra"]
        case "ico": args += ["-vf", "scale=256:256:force_original_aspect_ratio=decrease", "-c:v", "png"]
        default: args += ["-c:v", "png"]
        }
        args += ["-frames:v", "1", "-update", "1", path.path]
        _ = try await runFFmpeg(args)
        return path
    }

    // MARK: - 视频

    private static func compressVideo(input: URL,
                                      settings: ConversionSettings,
                                      output: URL,
                                      target: Int64,
                                      info: MediaInfo,
                                      progress: @escaping (Double, String) -> Void) async throws {
        guard info.duration > 0 else {
            throw Failure.engine(L10n.t("msg.noDuration"))
        }
        let audioKbps = info.hasAudio ? 128 : 0
        let budget = Double(target) * 0.97 - Double(target) * 0.015
        var totalKbps = budget * 8 / info.duration / 1000
        var videoKbps = Int(totalKbps) - audioKbps - 8
        if videoKbps < 60 {
            throw Failure.unreachable(target: target, best: Int64(Double(videoKbps + audioKbps + 8) / 8 * info.duration * 1000))
        }

        var targetHeight: Int? = nil
        if settings.allowDownscale, info.width > 0, info.height > 0 {
            let fps = 30.0
            var height = info.height
            while height > 240 {
                let bpp = Double(videoKbps) * 1000 / (Double(info.width) * Double(height) * fps)
                if bpp >= 0.06 { break }
                height = max(240, (height / 2) / 2 * 2)
                targetHeight = height
                videoKbps = Int(budget * 8 / info.duration / 1000) - audioKbps - 8
                if videoKbps < 40 { break }
            }
            if let height = targetHeight, height == info.height { targetHeight = nil }
        }

        var currentKbps = max(videoKbps, 40)
        var lastSize: Int64 = 0
        let passLog = FileManager.default.temporaryDirectory
            .appendingPathComponent("anyconvert-pass-\(UUID().uuidString.prefix(8))")

        for attempt in 0..<3 {
            try await twoPass(input: input, output: output, videoKbps: currentKbps,
                              audioKbps: audioKbps, height: targetHeight,
                              passLog: passLog, duration: info.duration, progress: progress)
            lastSize = fileSize(output)
            if lastSize <= Int64(Double(target) * 1.02) { return }
            if attempt == 2 { break }
            let ratio = Double(target) / Double(max(lastSize, 1))
            currentKbps = max(40, Int(Double(currentKbps) * ratio * 0.92))
            if currentKbps < 40 { break }
        }

        cleanupPassLogs(passLog)
        try? FileManager.default.removeItem(at: output)
        throw Failure.unreachable(target: target, best: lastSize)
    }

    private static func twoPass(input: URL, output: URL, videoKbps: Int, audioKbps: Int,
                                height: Int?, passLog: URL, duration: Double,
                                progress: @escaping (Double, String) -> Void) async throws {
        var base = ["-hide_banner", "-nostdin", "-y", "-i", input.path,
                    "-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn"]
        if let height {
            base += ["-vf", "scale=-2:\(height):flags=lanczos"]
        }
        base += ["-c:v", "libx264", "-preset", "medium", "-b:v", "\(videoKbps)k",
                 "-maxrate", "\(Int(Double(videoKbps) * 1.2))k",
                 "-bufsize", "\(videoKbps * 2)k",
                 "-pix_fmt", "yuv420p", "-passlogfile", passLog.path]

        _ = try await runFFmpeg(base + ["-pass", "1", "-an", "-f", "null",
                                        FileManager.default.temporaryDirectory.path + "/null.mp4"])

        var pass2 = base + ["-pass", "2"]
        if audioKbps > 0 { pass2 += ["-c:a", "aac", "-b:a", "\(audioKbps)k"] } else { pass2 += ["-an"] }
        pass2 += ["-movflags", "+faststart", output.path]

        try await Engine.shared.run(arguments: pass2, duration: duration) { percent, speed in
            progress(percent, speed)
        }
        cleanupPassLogs(passLog)
    }

    private static func cleanupPassLogs(_ prefix: URL) {
        let dir = prefix.deletingLastPathComponent()
        let base = prefix.lastPathComponent
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasPrefix(base) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    // MARK: - 基础

    private static func runFFmpeg(_ args: [String]) async throws -> String {
        guard let ffmpeg = Toolchain.ffmpeg else { throw Failure.engine(L10n.t("msg.noEngine")) }
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        try process.run()
        let status: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
        }
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        if status != 0 {
            let detail = text.split(separator: "\n").suffix(2).joined(separator: " · ")
            throw Failure.engine(detail.isEmpty ? "FFmpeg \(status)" : detail)
        }
        return text
    }

    private static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    private static func replace(_ source: URL, with destination: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: source, to: destination)
    }
}
