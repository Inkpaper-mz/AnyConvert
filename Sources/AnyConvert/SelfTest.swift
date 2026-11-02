import Foundation

// 无 GUI 的自检：验证引擎定位、参数生成与真实转码链路。
enum SelfTest {
    static func run() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        Task {
            success = await perform()
            semaphore.signal()
        }
        semaphore.wait()
        return success
    }

    private static func perform() async -> Bool {
        print("== 万能转码 自检 ==")
        guard let ffmpeg = Toolchain.ffmpeg, Toolchain.ffprobe != nil else {
            print("✗ 找不到 FFmpeg / ffprobe")
            return false
        }
        print("FFmpeg: \(ffmpeg.path) — \(Toolchain.versionString())")

        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("anyconvert-selftest-\(ProcessInfo.processInfo.processIdentifier)")
        try? fm.removeItem(at: workDir)
        do {
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        } catch {
            print("✗ 无法创建临时目录：\(error)")
            return false
        }
        defer { try? fm.removeItem(at: workDir) }

        // 1. 生成测试素材
        let sample = workDir.appendingPathComponent("sample.mp4")
        let make = Process()
        make.executableURL = ffmpeg
        make.arguments = [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=480x270:rate=25:duration=3",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=3",
            "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "128k", "-shortest", sample.path,
        ]
        make.standardError = Pipe()
        do {
            try make.run()
            make.waitUntilExit()
        } catch {
            print("✗ 生成测试素材失败：\(error)")
            return false
        }
        guard make.terminationStatus == 0 else {
            print("✗ 生成测试素材失败（status \(make.terminationStatus)）")
            return false
        }

        // 静态图片素材（用于图片→图片测试）
        let stillImage = workDir.appendingPathComponent("still.png")
        let still = Process()
        still.executableURL = ffmpeg
        still.arguments = ["-hide_banner", "-loglevel", "error", "-y", "-i", sample.path,
                           "-frames:v", "1", "-update", "1", stillImage.path]
        still.standardError = Pipe()
        try? still.run()
        still.waitUntilExit()

        guard let info = try? MediaProbe.probeSync(sample) else {
            print("✗ 无法解析测试素材")
            return false
        }
        print("素材：\(info.width)×\(info.height) · \(String(format: "%.2f", info.duration))s · video=\(info.hasVideo) audio=\(info.hasAudio)")

        // 2. 校验：所有格式都能生成完整参数
        let mediaFormats = Catalog.all.filter { $0.kind != .document }
        var argFailures = 0
        for format in mediaFormats {
            let output = workDir.appendingPathComponent("check.\(format.ext)")
            let settings = ConversionSettings(format: format, quality: .balanced, resolution: .original, audioBitrate: .b192, hardware: false)
            let args = CommandBuilder.arguments(settings: settings, input: sample, output: output, info: info)
            let valid = args.contains("-i") && args.last == output.path && !args.isEmpty
            if !valid {
                argFailures += 1
                print("✗ 参数异常：\(format.id)")
            }
        }
        print("参数生成：\(mediaFormats.count) 种媒体格式，失败 \(argFailures)（文档格式由 LibreOffice/PDFKit 处理，单独校验）")

        // 3. 真实转码
        let targets = mediaFormats.map(\.id)
        var failures: [String] = []
        var timings: [(String, Double, Int64)] = []

        for id in targets {
            let format = Catalog.format(id)
            let output = workDir.appendingPathComponent("out-\(id).\(format.ext)")
            let settings = ConversionSettings(format: format, quality: .small, resolution: .original, audioBitrate: .b128, hardware: false)
            let args = CommandBuilder.arguments(settings: settings, input: sample, output: output, info: info)
            let started = Date()
            do {
                try await Engine.shared.run(arguments: args, duration: info.duration) { _, _ in }
                let elapsed = Date().timeIntervalSince(started)
                let size = ((try? fm.attributesOfItem(atPath: output.path)[.size]) as? NSNumber)?.int64Value ?? 0
                let produced = try MediaProbe.probeSync(output)
                let expectedAudio = format.kind == .audio
                let ok = size > 0 && (expectedAudio ? produced.hasAudio : produced.hasVideo)
                let kindText = expectedAudio ? "audio" : "video"
                if ok {
                    print(String(format: "✓ %-5@ → %-6@ %6.2fs %6lld KB", id, kindText, elapsed, size / 1024))
                    timings.append((id, elapsed, size))
                } else {
                    print("✗ \(id) 输出无效（size=\(size), audio=\(produced.hasAudio), video=\(produced.hasVideo)）")
                    failures.append(id)
                }
            } catch {
                print("✗ \(id) 失败：\(error.localizedDescription)")
                failures.append(id)
            }
        }

        // 3b. 图片 → 图片
        var imageFailures: [String] = []
        if still.terminationStatus == 0 {
            for format in Catalog.imageFormats {
                let output = workDir.appendingPathComponent("img-\(format.id).\(format.ext)")
                let settings = ConversionSettings(format: format, quality: .small, resolution: .original,
                                                  audioBitrate: .b128, hardware: false)
                let args = CommandBuilder.arguments(settings: settings, input: stillImage, output: output, info: info)
                do {
                    try await Engine.shared.run(arguments: args, duration: 0) { _, _ in }
                    let size = ((try? fm.attributesOfItem(atPath: output.path)[.size]) as? NSNumber)?.int64Value ?? 0
                    let produced = try MediaProbe.probeSync(output)
                    if size > 0, produced.hasVideo, produced.width > 0 {
                        print(String(format: "✓ png → %-4@ %6lld KB  %@", format.id, size / 1024, produced.resolutionText))
                    } else {
                        imageFailures.append(format.id)
                        print("✗ png → \(format.id) 输出无效")
                    }
                } catch {
                    imageFailures.append(format.id)
                    print("✗ png → \(format.id) 失败：\(error.localizedDescription)")
                }
            }
        }

        // 4. 硬件编码（可选，失败不算致命）
        if Toolchain.supportsVideoToolbox() {
            let output = workDir.appendingPathComponent("hw.mp4")
            let settings = ConversionSettings(format: Catalog.format("mp4"), quality: .balanced, resolution: .original, audioBitrate: .b192, hardware: true)
            let args = CommandBuilder.arguments(settings: settings, input: sample, output: output, info: info)
            do {
                try await Engine.shared.run(arguments: args, duration: info.duration) { _, _ in }
                let size = ((try? fm.attributesOfItem(atPath: output.path)[.size]) as? NSNumber)?.int64Value ?? 0
                print(size > 0 ? "✓ VideoToolbox 硬件编码正常（\(size / 1024) KB）" : "△ VideoToolbox 输出为空")
            } catch {
                print("△ VideoToolbox 不可用（应用会自动回退软编）：\(error.localizedDescription)")
            }
        }

        print("--------------------------------")
        let allFailures = failures + imageFailures
        if allFailures.isEmpty && argFailures == 0 {
            print("结果：全部通过 ✅  （\(targets.count) 种格式 + 图片互转 \(Catalog.imageFormats.count) 项）")
            return true
        }
        print("结果：失败 \(allFailures.count) 项 → \(allFailures.joined(separator: ", "))")
        return false
    }
}
