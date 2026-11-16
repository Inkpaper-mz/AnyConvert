import Foundation

/// libvips 将 SVG 栅格化为临时 PNG，后续沿用媒体转换流程。
enum ProfessionalImage {
    static let rawExtensions: Set<String> = ["arw", "cr2", "cr3", "crw", "nef", "nrw", "raf", "dng", "orf", "rw2", "pef", "srw", "3fr", "iiq", "kdc", "dcr", "mos", "mrw", "x3f"]
    static func needsRasterization(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "svg" || rawExtensions.contains(url.pathExtension.lowercased())
    }

    static func rasterize(_ source: URL) throws -> URL {
        let isRaw = rawExtensions.contains(source.pathExtension.lowercased())
        guard let helper = Toolchain.locate(isRaw ? "dcraw_emu" : "vips-helper") else {
            throw ConvertError.encodeFailed(isRaw ? "RAW 引擎未安装" : "SVG 引擎未安装")
        }
        let fm = FileManager.default
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("bin/libvips-cpp.8.18.7.dylib"),
                          URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("vendor/libvips/libvips-cpp.8.18.7.dylib")].compactMap { $0 }
        let library = candidates.first(where: { fm.fileExists(atPath: $0.path) })
        if !isRaw && library == nil { throw ConvertError.encodeFailed("SVG 引擎组件缺失") }
        let dir = fm.temporaryDirectory.appendingPathComponent("anyconvert-svg-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let output = dir.appendingPathComponent(isRaw ? "image.ppm" : "image.png")
        let process = Process()
        process.executableURL = helper
        process.arguments = isRaw ? ["-w", "-Z", output.path, source.path] : [library!.path, source.path, output.path]
        let error = Pipe()
        process.standardError = error
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: timeout)
            let data = error.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeout.cancel()
            guard process.terminationStatus == 0, fm.fileExists(atPath: output.path) else {
                let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                throw ConvertError.encodeFailed(message.isEmpty ? (isRaw ? "RAW 解码失败" : "SVG 解码失败") : message)
            }
            return output
        } catch {
            try? fm.removeItem(at: dir)
            throw error
        }
    }

    static func cleanup(_ url: URL) { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}
