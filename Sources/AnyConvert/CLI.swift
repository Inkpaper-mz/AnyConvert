import Foundation

/// 命令行模式：`AnyConvert --cli -i input.mp4 --to mp3 [--json]`
/// 与 GUI 共用 MediaProbe / CommandBuilder / Engine，便于自动化与后续跨平台复用。
enum CLI {
    static func run(_ arguments: [String]) -> Int32 {
        var input: String?
        var target = "mp3"
        var outputDir: String?
        var quality = Quality.balanced
        var resolution = ResolutionPreset.original
        var bitrate = AudioBitrate.b192
        var width: Int?
        var height: Int?
        var hardware = false
        var json = false
        var showCapabilities = false
        var targetsFor: String?
        var quiet = false

        var index = 0
        func next() -> String? {
            index += 1
            return index < arguments.count ? arguments[index] : nil
        }

        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "-i", "--input": input = next()
            case "--to", "-f", "--format": target = next() ?? target
            case "-o", "--output", "--output-dir": outputDir = next()
            case "-q", "--quality":
                if let raw = next(), let value = Quality(rawValue: raw) { quality = value }
            case "-r", "--resolution":
                if let raw = next(), let value = ResolutionPreset(rawValue: raw) { resolution = value }
            case "-b", "--bitrate":
                if let raw = next(), let value = AudioBitrate(rawValue: raw + "k") ?? AudioBitrate(rawValue: raw) {
                    bitrate = value
                }
            case "--width": width = next().flatMap(Int.init)
            case "--height": height = next().flatMap(Int.init)
            case "--hw", "--hardware": hardware = true
            case "--json": json = true
            case "--quiet": quiet = true
            case "--capabilities": showCapabilities = true
            case "--targets": targetsFor = next()
            case "--help", "-h":
                printHelp()
                return 0
            default:
                break
            }
            index += 1
        }

        if showCapabilities {
            printCapabilities(json: json)
            return 0
        }

        if let targetsFor {
            return printTargets(for: targetsFor, json: json)
        }

        guard let input else {
            return fail("missing --input", code: "E_ARGS", json: json)
        }

        let source = URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: source.path) else {
            return fail("input not found: \(source.path)", code: "E_NO_INPUT", json: json)
        }
        guard let ffmpeg = Toolchain.ffmpeg, Toolchain.ffprobe != nil else {
            return fail("ffmpeg not found", code: "E_NO_ENGINE", json: json)
        }

        let info: MediaInfo
        do {
            info = try MediaProbe.probeSync(source)
        } catch {
            return fail(error.localizedDescription, code: "E_PROBE", json: json)
        }

        guard let format = Catalog.all.first(where: { $0.id == target }) else {
            return fail("unknown target: \(target)", code: "E_TARGET", json: json)
        }
        if format.kind == .audio, !info.hasAudio {
            return fail("no audio track", code: "E_NO_AUDIO", json: json)
        }
        if format.kind == .video, !info.hasVideo {
            return fail("no video track", code: "E_NO_VIDEO", json: json)
        }
        if format.kind == .image, !info.hasVideo {
            return fail("no video/image track", code: "E_NO_IMAGE", json: json)
        }
        if format.kind == .video, info.isImage, format.id != "gif" {
            return fail("image input can only target image or GIF", code: "E_IMAGE_ONLY", json: json)
        }

        let directory = outputDir.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? source.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = FileUtilities.outputURL(for: source, ext: format.ext, directory: directory)

        let settings = ConversionSettings(format: format, quality: quality, resolution: resolution,
                                          audioBitrate: bitrate, hardware: hardware,
                                          customWidth: width, customHeight: height)
        guard let engine = EngineRegistry.engine(for: format),
              let args = engine.arguments(for: settings, input: source, output: output, info: info) else {
            return fail("no engine for \(format.id)", code: "E_NO_ENGINE", json: json)
        }

        let started = Date()
        var lastPercent = -1
        var exitCode: Int32 = 0
        var message = ""

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                try await Engine.shared.run(arguments: args, duration: info.duration) { percent, _ in
                    guard !json, !quiet else { return }
                    let value = Int(percent * 100)
                    if value != lastPercent {
                        lastPercent = value
                        FileHandle.standardError.write(Data("\r  \(value)%".utf8))
                    }
                }
            } catch {
                exitCode = 1
                message = error.localizedDescription
            }
            semaphore.signal()
        }
        semaphore.wait()

        if !json, !quiet { FileHandle.standardError.write(Data("\n".utf8)) }
        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)

        if exitCode != 0 {
            return fail(message.isEmpty ? "conversion failed" : message, code: "E_CONVERT", json: json)
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)??.int64Value ?? 0
        guard size > 0 else {
            return fail("empty output", code: "E_EMPTY", json: json)
        }

        if json {
            let payload: [String: Any] = [
                "ok": true,
                "input": source.path,
                "output": output.path,
                "format": format.id,
                "bytes": size,
                "elapsedMs": elapsedMs,
                "engine": engine.displayName,
            ]
            printJSON(payload)
        } else {
            print(output.path)
        }
        _ = ffmpeg
        return 0
    }

    // MARK: - 辅助

    private static func printHelp() {
        print("""
        万能转码 CLI
          AnyConvert --cli -i <input> --to <format> [options]
          AnyConvert --cli --capabilities [--json]
          AnyConvert --cli --targets <file|ext> [--json]

        选项:
          -i, --input <file>        输入文件
          --to, -f <format>         目标格式 id（默认 mp3）
          -o, --output <dir>        输出目录（默认源文件目录）
          -q, --quality <high|balanced|small>
          -r, --resolution <original|uhd4k|fhd1080|hd720|sd480|sd360|custom>
          --width <n> --height <n>  自定义尺寸
          -b, --bitrate <128|192|256|320>
          --hw                      Apple VideoToolbox 硬件编码
          --json                    JSON 输出（成功 stdout / 失败 stderr）
          --quiet                   不打印进度
        """)
    }

    private static func printCapabilities(json: Bool) {
        let groups: [String: Any] = [
            "video": ["inputs": ["mp4", "mov", "mkv", "avi", "webm", "wmv", "flv", "ts", "mpg", "3gp", "ogv", "gif"],
                      "targets": Catalog.videoFormats.map(\.id)],
            "audio": ["targets": Catalog.audioFormats.map(\.id)],
            "image": ["targets": Catalog.imageFormats.map(\.id)],
        ]
        let payload: [String: Any] = [
            "ok": true,
            "version": "1.2.0",
            "engine": Toolchain.versionString(),
            "groups": groups,
            "formats": Catalog.all.map { ["id": $0.id, "kind": $0.kind.rawValue, "ext": $0.ext] },
        ]
        if json { printJSON(payload) } else { print(payload) }
    }

    private static func printTargets(for value: String, json: Bool) -> Int32 {
        let path = (value as NSString).expandingTildeInPath
        let fm = FileManager.default
        let info: MediaInfo
        let ext: String
        if fm.fileExists(atPath: path) {
            do { info = try MediaProbe.probeSync(URL(fileURLWithPath: path)) }
            catch { return fail(error.localizedDescription, code: "E_PROBE", json: json) }
            ext = (path as NSString).pathExtension.lowercased()
        } else {
            ext = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            info = MediaInfo()
        }

        var targets: [OutputFormat]
        if info.hasAudio || info.hasVideo || info.isImage {
            targets = Catalog.all.filter { format in
                switch format.kind {
                case .audio: return info.hasAudio
                case .video: return info.hasVideo && (!info.isImage || format.id == "gif")
                case .image: return info.hasVideo
                }
            }
        } else {
            targets = Catalog.all.filter { format in
                switch ext {
                case "png", "jpg", "jpeg", "webp", "avif", "tiff", "tif", "bmp", "ico", "heic":
                    return format.kind == .image || format.id == "gif"
                case "mp3", "wav", "flac", "aac", "m4a", "ogg", "opus", "wma", "aiff", "aif", "ac3", "caf":
                    return format.kind == .audio
                default:
                    return true
                }
            }
        }
        let payload: [String: Any] = [
            "ok": true,
            "extension": ext,
            "targets": targets.map { ["id": $0.id, "kind": $0.kind.rawValue, "ext": $0.ext] },
        ]
        if json { printJSON(payload) } else { targets.forEach { print("\($0.id)\t\($0.kind.rawValue)\t\($0.ext)") } }
        return 0
    }

    private static func printJSON(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        print(text)
    }

    private static func fail(_ message: String, code: String, json: Bool) -> Int32 {
        if json {
            let payload: [String: Any] = ["ok": false, "error": message, "errorCode": code]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                FileHandle.standardError.write(Data((text + "\n").utf8))
            }
        } else {
            FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
        }
        return 1
    }
}
