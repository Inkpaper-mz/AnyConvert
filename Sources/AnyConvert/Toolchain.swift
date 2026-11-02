import Foundation

/// 定位随 App 打包的 FFmpeg / ffprobe，并回退到系统已安装的版本。
enum Toolchain {
    private static var cachedFFmpeg: URL?
    private static var cachedFFprobe: URL?
    private static var cachedVersion: String?

    /// 当前进程架构后缀：arm64 / x86_64
    static var archSuffix: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "arm64"
        #endif
    }

    static var ffmpeg: URL? {
        if let u = cachedFFmpeg { return u }
        cachedFFmpeg = locate("ffmpeg")
        return cachedFFmpeg
    }

    static var ffprobe: URL? {
        if let u = cachedFFprobe { return u }
        cachedFFprobe = locate("ffprobe")
        return cachedFFprobe
    }

    static func locate(_ name: String) -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []

        // 1. App 包内 Resources/bin（按架构优先）
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("bin/\(name)-\(archSuffix)"))
            candidates.append(resources.appendingPathComponent("bin/\(name)"))
        }

        // 2. 环境变量指定的目录
        if let dir = ProcessInfo.processInfo.environment["ANYCONVERT_BIN"] {
            candidates.append(URL(fileURLWithPath: dir).appendingPathComponent(name))
        }

        // 3. 开发模式：工程目录下的 vendor
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("vendor/\(name)-\(archSuffix)"))
        candidates.append(cwd.appendingPathComponent("vendor/\(name)"))
        candidates.append(cwd.appendingPathComponent("AnyConvert/vendor/\(name)"))
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(exeDir.appendingPathComponent("vendor/\(name)"))
            candidates.append(exeDir.deletingLastPathComponent().appendingPathComponent("vendor/\(name)"))
            candidates.append(exeDir.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("vendor/\(name)"))
        }

        // 4. 常见安装位置
        candidates += [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/opt/local/bin/\(name)",
        ].map(URL.init(fileURLWithPath:))

        for url in candidates where fm.isExecutableFile(atPath: url.path) {
            return url
        }

        // 5. PATH
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let url = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
                if fm.isExecutableFile(atPath: url.path) { return url }
            }
        }
        return nil
    }

    /// 形如 "FFmpeg 9.0.2"
    static func versionString() -> String {
        if let v = cachedVersion { return v }
        guard let ffmpeg else { return "FFmpeg 未找到" }
        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = ["-hide_banner", "-version"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            if let first = text.split(separator: "\n").first {
                // "ffmpeg version 9.0.2-https://... Copyright ..."
                let parts = first.split(separator: " ")
                if parts.count >= 3 {
                    var v = String(parts[2])
                    if let dash = v.firstIndex(of: "-") { v = String(v[..<dash]) }
                    let result = "FFmpeg \(v)"
                    cachedVersion = result
                    return result
                }
            }
        } catch {
            return "FFmpeg 不可用"
        }
        cachedVersion = "FFmpeg"
        return "FFmpeg"
    }

    /// 是否支持 Apple 硬件编码
    static func supportsVideoToolbox() -> Bool {
        guard let ffmpeg else { return false }
        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = ["-hide_banner", "-encoders"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(decoding: data, as: UTF8.self).contains("h264_videotoolbox")
        } catch {
            return false
        }
    }
}
