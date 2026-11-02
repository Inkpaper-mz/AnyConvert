import Foundation

/// 使用 ffprobe 读取媒体信息（时长、分辨率、音视频轨）。
enum MediaProbe {
    static func probe(_ url: URL) async throws -> MediaInfo {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<MediaInfo, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    cont.resume(returning: try probeSync(url))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    static func probeSync(_ url: URL) throws -> MediaInfo {
        guard let ffprobe = Toolchain.ffprobe else { throw ConvertError.toolchainMissing }

        let process = Process()
        process.executableURL = ffprobe
        process.arguments = [
            "-v", "error",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            url.path,
        ]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            throw ConvertError.probeFailed("无法启动解析引擎")
        }

        // 20 秒超时保护（损坏文件可能让 ffprobe 卡住）
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)

        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()

        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errData, as: UTF8.self)
                .split(separator: "\n")
                .last.map(String.init) ?? "解析失败"
            throw ConvertError.probeFailed(detail)
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConvertError.probeFailed("输出格式异常")
        }

        var info = MediaInfo()

        if let format = root["format"] as? [String: Any] {
            if let d = format["duration"] as? String, let v = Double(d) { info.duration = v }
            if let name = format["format_name"] as? String { info.container = name }
        }

        if let streams = root["streams"] as? [[String: Any]] {
            for stream in streams {
                let type = stream["codec_type"] as? String ?? ""
                if type == "video", !info.hasVideo {
                    // 跳过封面图（attached_pic）
                    let disposition = stream["disposition"] as? [String: Any]
                    let attached = (disposition?["attached_pic"] as? Int) == 1
                    if attached { continue }
                    info.hasVideo = true
                    info.width = stream["width"] as? Int ?? 0
                    info.height = stream["height"] as? Int ?? 0
                    info.videoCodec = stream["codec_name"] as? String ?? ""
                } else if type == "audio", !info.hasAudio {
                    info.hasAudio = true
                    info.audioCodec = stream["codec_name"] as? String ?? ""
                }
            }
        }

        if info.duration <= 0 {
            // 部分流（如 TS）format.duration 缺失，尝试取流时长
            if let streams = root["streams"] as? [[String: Any]] {
                for stream in streams {
                    if let d = stream["duration"] as? String, let v = Double(d), v > 0 {
                        info.duration = max(info.duration, v)
                    }
                }
            }
        }

        guard info.hasVideo || info.hasAudio else {
            throw ConvertError.probeFailed("没有可转换的音视频轨")
        }
        return info
    }
}
