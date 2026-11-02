import Foundation

/// 首次运行从清华 TUNA 镜像下载 LibreOffice，安装到用户目录（无需管理员）。
enum EngineInstaller {
    static let version = "26.8.2"
    static let base = "https://mirrors.tuna.tsinghua.edu.cn/libreoffice/libreoffice/stable"

    enum Failure: LocalizedError {
        case download(String)
        case mount
        case install(String)

        var errorDescription: String? {
            switch self {
            case .download(let detail): return "下载失败：\(detail)"
            case .mount: return "无法挂载 LibreOffice 安装包"
            case .install(let detail): return "安装失败：\(detail)"
            }
        }
    }

    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AnyConvert")
    }

    static var installedApp: URL {
        supportDirectory.appendingPathComponent("LibreOffice.app")
    }

    static func downloadURL() -> URL {
        #if arch(arm64)
        let arch = "aarch64"
        #else
        let arch = "x86-64"
        #endif
        let name = "LibreOffice_\(version)_MacOS_\(arch).dmg"
        return URL(string: "\(base)/\(version)/mac/\(arch)/\(name)")!
    }

    static func install(progress: @escaping (Double, String) -> Void) async throws {
        let url = downloadURL()
        progress(0.05, "正在下载 LibreOffice（约 300 MB）…")

        let (temporary, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure.download("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        progress(0.75, "下载完成，正在挂载…")

        let mountPoint = try await Task.detached(priority: .userInitiated) { () throws -> String in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["attach", "-nobrowse", "-readonly", temporary.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw Failure.mount }
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            guard let line = output.split(separator: "\n").first(where: { $0.contains("/Volumes/") }),
                  let range = line.range(of: "/Volumes/") else { throw Failure.mount }
            return String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
        }.value

        let source = URL(fileURLWithPath: mountPoint).appendingPathComponent("LibreOffice.app")
        progress(0.82, "正在复制 LibreOffice（约 800 MB）…")
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            if fm.fileExists(atPath: installedApp.path) {
                try fm.removeItem(at: installedApp)
            }
            try fm.copyItem(at: source, to: installedApp)
        }.value

        _ = try? await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["detach", mountPoint]
            try? process.run()
            process.waitUntilExit()
        }.value

        try? FileManager.default.removeItem(at: temporary)
        guard FileManager.default.isExecutableFile(atPath: DocumentEngine.installedSofficePath) else {
            throw Failure.install("未找到 soffice")
        }
        progress(1.0, "LibreOffice 已就绪")
    }
}
