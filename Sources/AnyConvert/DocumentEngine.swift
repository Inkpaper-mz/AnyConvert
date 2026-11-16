import AppKit
import Foundation
import PDFKit
import Vision

/// 原生文档 / PDF / OCR 引擎：LibreOffice（文档互转）+ PDFKit（PDF 工具）+ Vision（OCR）。
enum DocumentEngine {

    enum Failure: LocalizedError {
        case engineMissing
        case unsupported(String, String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .engineMissing:
                return L10n.t("msg.docEngine")
            case .unsupported(let target, let source):
                return L10n.t("msg.docUnsupported", source, target)
            case .failed(let detail):
                return detail
            }
        }
    }

    static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "wps", "odt", "rtf", "txt", "md", "html", "htm",
        "xls", "xlsx", "ods", "et", "csv", "json", "ppt", "pptx", "odp", "dps", "dpt",
    ]
    static let imageExtensions: Set<String> = Set([
        "jpg", "jpeg", "png", "webp", "avif", "tiff", "tif", "bmp", "ico", "heic", "heif", "svg",
    ]).union(ProfessionalImage.rawExtensions)

    /// 目标 → 允许的源格式（与跨平台矩阵保持一致的核心子集）
    static let matrix: [String: Set<String>] = [
        "pdf": documentExtensions.union(imageExtensions).union(["epub"]),
        "docx": ["doc", "wps", "odt", "rtf", "txt", "md", "html", "htm", "pdf", "csv", "json"],
        "odt": ["doc", "docx", "wps", "rtf", "txt", "md", "html", "htm", "pdf"],
        "rtf": ["doc", "docx", "wps", "odt", "txt", "md", "html", "htm", "pdf"],
        "txt": Set(["doc", "docx", "wps", "odt", "rtf", "pdf", "md", "html", "htm", "csv", "xlsx", "json"]).union(imageExtensions),
        "md": ["docx", "odt", "html", "htm", "txt", "pdf", "csv", "json"],
        "html": ["doc", "docx", "wps", "odt", "rtf", "txt", "md", "pdf", "csv", "json"],
        "xlsx": ["xls", "ods", "et", "csv", "tsv"],
        "csv": ["xls", "xlsx", "ods", "et", "tsv", "json", "md", "html", "htm", "txt"],
        "json": ["csv", "txt", "md", "html", "htm"],
        "pptx": ["ppt", "odp", "dps", "dpt", "pdf"],
        "png": ["pdf"],
        "jpg": ["pdf"],
        "jpeg": ["pdf"],
    ]

    static func isDocument(_ ext: String) -> Bool {
        documentExtensions.contains(ext.lowercased())
    }

    static func isImage(_ ext: String) -> Bool {
        imageExtensions.contains(ext.lowercased())
    }

    static func canConvert(target: String, sourceExt: String) -> Bool {
        guard let allowed = matrix[target.lowercased()] else { return false }
        return allowed.contains(sourceExt.lowercased())
    }

    // MARK: - 入口

    static func convert(src: URL, target: OutputFormat, output: URL,
                        progress: @escaping (Double) -> Void) async throws {
        let sourceExt = src.pathExtension.lowercased()
        let ext = target.ext.lowercased()
        guard canConvert(target: ext, sourceExt: sourceExt) else {
            throw Failure.unsupported(ext, sourceExt)
        }
        progress(0.05)
        if (sourceExt == "csv" && ext == "json") || (sourceExt == "json" && ext == "csv") {
            try StructuredText.convert(src, target: ext, output: output)
            progress(1)
            return
        }
        if ["md", "html", "htm"].contains(sourceExt) && ["csv", "json"].contains(ext) {
            guard let pandoc = Toolchain.locate("pandoc") else { throw Failure.failed("表格转换需要内置 Pandoc 引擎") }
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("anyconvert-table-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: work) }
            let ast = work.appendingPathComponent("table.json")
            let result = try await run(pandoc.path, ["--from", sourceExt == "md" ? "markdown" : "html", "--to", "json", "--output", ast.path, src.path], timeout: 300)
            guard result.status == 0 else { throw Failure.failed(result.error.isEmpty ? "无法解析表格" : result.error) }
            let csv = ext == "csv" ? output : work.appendingPathComponent("table.csv")
            try StructuredText.tableASTToCSV(Data(contentsOf: ast), output: csv)
            if ext == "json" { try StructuredText.convert(csv, target: "json", output: output) }
            progress(1)
            return
        }
        if sourceExt == "txt" && ext == "csv" {
            // 只有本身是有效 CSV 的文本才能转为 CSV，不能把任意正文伪装成表格。
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("anyconvert-text-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: work) }
            let csv = work.appendingPathComponent("input.csv")
            try FileManager.default.copyItem(at: src, to: csv)
            try StructuredText.convert(csv, target: "json", output: work.appendingPathComponent("validate.json"))
            try Data(contentsOf: csv).write(to: output, options: .atomic)
            progress(1)
            return
        }
        if sourceExt == "txt" && ext == "json" {
            let text = try String(contentsOf: src, encoding: .utf8)
            let data = try JSONSerialization.data(withJSONObject: ["text": text], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output, options: .atomic)
            progress(1)
            return
        }
        if sourceExt == "json" && ext == "txt" {
            let data = try Data(contentsOf: src)
            let object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            if let dict = object as? [String: Any], dict.count == 1, let text = dict["text"] as? String {
                try text.write(to: output, atomically: true, encoding: .utf8)
            } else {
                let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
                try pretty.write(to: output, options: .atomic)
            }
            progress(1)
            return
        }
        if ["csv", "json"].contains(sourceExt) && ["md", "html", "docx", "pdf"].contains(ext) {
            guard let pandoc = Toolchain.locate("pandoc") else { throw Failure.failed("转换需要内置 Pandoc 引擎") }
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("anyconvert-table-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: work) }
            var input = src
            let inputFormat = "csv"
            if sourceExt == "json" {
                input = work.appendingPathComponent("table.csv")
                try StructuredText.convert(src, target: "csv", output: input)
            }
            let destination = ext == "pdf" ? work.appendingPathComponent("table.docx") : output
            let outputFormat = ext == "pdf" ? "docx" : (ext == "md" ? "markdown" : ext)
            let result = try await run(pandoc.path, ["--from", inputFormat, "--to", outputFormat,
                                                      "--output", destination.path, input.path], timeout: 300)
            guard result.status == 0, FileManager.default.fileExists(atPath: destination.path) else {
                throw Failure.failed(result.error.isEmpty ? "表格转换失败" : result.error)
            }
            if ext == "pdf" { try await libreOfficeConvert(src: destination, ext: "pdf", output: output) }
            progress(1)
            return
        }
        if sourceExt == "pdf" && ext == "md" {
            // PDF 的文字层缺少可靠的文档结构；不猜测标题或表格，保留文本和换行。
            let text = try pdfText(src)
            let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "*", with: "\\*")
                .replacingOccurrences(of: "_", with: "\\_")
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
                .replacingOccurrences(of: "#", with: "\\#")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            try escaped.components(separatedBy: "\n").joined(separator: "  \n").write(to: output, atomically: true, encoding: .utf8)
            progress(1)
            return
        }
        if sourceExt == "md" || ext == "md" || (["html", "htm"].contains(sourceExt) && ext == "docx") {
            guard let pandoc = Toolchain.locate("pandoc") else {
                throw Failure.failed("Markdown 转换需要内置 Pandoc 引擎")
            }
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("anyconvert-pandoc-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: work) }
            let destination = ext == "pdf" ? work.appendingPathComponent("document.docx") : output
            let inputFormat = ["md", "txt"].contains(sourceExt) ? "markdown" : (sourceExt == "htm" ? "html" : sourceExt)
            let outputFormat = ext == "pdf" ? "docx" : (ext == "md" ? "markdown" : (ext == "txt" ? "plain" : ext))
            var args = ["--from", inputFormat, "--to", outputFormat, "--output", destination.path]
            if ext == "md" && ["docx", "odt"].contains(sourceExt) {
                let media = output.deletingPathExtension().lastPathComponent + "-media"
                args += ["--extract-media", output.deletingLastPathComponent().appendingPathComponent(media).path]
            }
            args.append(src.path)
            let result = try await run(pandoc.path, args, timeout: 300)
            guard result.status == 0, FileManager.default.fileExists(atPath: destination.path) else {
                throw Failure.failed(result.error.isEmpty ? "Pandoc 转换失败" : result.error)
            }
            if ext == "pdf" { try await libreOfficeConvert(src: destination, ext: "pdf", output: output) }
            progress(1)
            return
        }

        if ext == "pdf" {
            if isImage(sourceExt) {
                if ProfessionalImage.needsRasterization(src) {
                    let raster = try await Task.detached(priority: .userInitiated) { try ProfessionalImage.rasterize(src) }.value
                    defer { ProfessionalImage.cleanup(raster) }
                    try imagesToPDF([raster], output: output)
                } else { try imagesToPDF([src], output: output) }
                progress(1)
                return
            }
            try await libreOfficeConvert(src: src, ext: ext, output: output)
            progress(1)
            return
        }

        if ext == "txt", isImage(sourceExt) {
            let raster: URL
            if ProfessionalImage.needsRasterization(src) {
                raster = try await Task.detached(priority: .userInitiated) { try ProfessionalImage.rasterize(src) }.value
            } else { raster = src }
            defer { if raster != src { ProfessionalImage.cleanup(raster) } }
            let text = try ocrText(imageURL: raster)
            try text.write(to: output, atomically: true, encoding: .utf8)
            progress(1)
            return
        }

        if isDocument(sourceExt) || sourceExt == "csv" {
            if ext == "png" || ext == "jpg" || ext == "jpeg" {
                try renderPDF(src: src, ext: ext, output: output)
                progress(1)
                return
            }
            if ext == "txt", sourceExt == "pdf" {
                let text = try pdfText(src)
                try text.write(to: output, atomically: true, encoding: .utf8)
                progress(1)
                return
            }
        }

        try await libreOfficeConvert(src: src, ext: ext, output: output)
        progress(1)
    }

    // MARK: - LibreOffice

    static var installedSofficePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AnyConvert/LibreOffice.app/Contents/MacOS/soffice")
            .path
    }

    static func findSoffice() -> URL? {
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["SOFFICE"] {
            candidates.append(URL(fileURLWithPath: env))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("LibreOffice.app/Contents/MacOS/soffice"))
        }
        candidates.append(URL(fileURLWithPath: "/Applications/LibreOffice.app/Contents/MacOS/soffice"))
        candidates.append(URL(fileURLWithPath: installedSofficePath))
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("crossplatform/vendor/LibreOffice.app/Contents/MacOS/soffice"))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func libreOfficeConvert(src: URL, ext: String, output: URL) async throws {
        guard let soffice = findSoffice() else { throw Failure.engineMissing }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("anyconvert-lo-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let profile = FileManager.default.temporaryDirectory
            .appendingPathComponent("anyconvert-profile-\(UUID().uuidString.prefix(8))")
        // Writer 文档使用明确的 PDF 导出器，避免图片有损压缩或降采样。
        let writerFormats: Set<String> = ["doc", "docx", "wps", "odt", "rtf"]
        let conversion: String
        if ext == "pdf" && writerFormats.contains(src.pathExtension.lowercased()) {
            conversion = #"pdf:writer_pdf_Export:{"UseLosslessCompression":{"type":"boolean","value":"true"},"ReduceImageResolution":{"type":"boolean","value":"false"}}"#
        } else {
            conversion = ext
        }
        let args = [
            "--headless", "--norestore", "--nolockcheck", "--nodefault",
            "-env:UserInstallation=\(profile.absoluteString)",
            "--convert-to", conversion, "--outdir", work.path, src.path,
        ]
        // Headless LibreOffice 依赖 fontconfig；显式提供 macOS 字体目录，
        // 否则它可能只看到随 LibreOffice 附带的字体，导致中文显示为空白。
        let config = work.appendingPathComponent("fonts.conf")
        let bundledFonts = soffice.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/fonts/truetype").path
        let escaped = bundledFonts.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let fontConfig = """
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
        <fontconfig>
          <dir>/System/Library/Fonts</dir>
          <dir>/System/Library/Fonts/Supplemental</dir>
          <dir>/Library/Fonts</dir>
          <dir>/Network/Library/Fonts</dir>
          <dir prefix="home">Library/Fonts</dir>
          <dir>\(escaped)</dir>
          <cachedir prefix="xdg">fontconfig</cachedir>
        </fontconfig>
        """
        try fontConfig.write(to: config, atomically: true, encoding: .utf8)
        let result = try await run(soffice.path, args, timeout: 300,
                                   environment: ["FONTCONFIG_FILE": config.path])
        try? FileManager.default.removeItem(at: profile)
        guard result.status == 0 else {
            throw Failure.failed(result.error.isEmpty ? "LibreOffice 转换失败" : result.error)
        }
        let produced = (try? FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension.lowercased() == ext }
        guard let produced else {
            throw Failure.failed(result.error.isEmpty ? "LibreOffice 没有生成输出" : result.error)
        }
        if ext == "pdf" {
            guard let pdf = PDFDocument(url: produced), pdf.pageCount > 0 else {
                throw Failure.failed("导出的 PDF 无法读取或没有页面，请检查源文档后重试")
            }
        }
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.moveItem(at: produced, to: output)
    }

    // MARK: - PDFKit

    static func renderPDF(src: URL, ext: String, output: URL) throws {
        guard let document = PDFDocument(url: src), let page = document.page(at: 0) else {
            throw Failure.failed("无法读取 PDF")
        }
        guard document.pageCount == 1 else {
            throw Failure.failed("此转换只能处理单页 PDF。请使用工具箱中的“PDF 转图片”导出所有页面。")
        }
        let scale: CGFloat = 2.0
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: max(bounds.width * scale, 16), height: max(bounds.height * scale, 16))
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            throw Failure.failed("PDF 渲染失败")
        }
        let isPNG = ext == "png"
        guard let data = rep.representation(using: isPNG ? .png : .jpeg,
                                            properties: isPNG ? [:] : [.compressionFactor: 0.9]) else {
            throw Failure.failed("图片编码失败")
        }
        try data.write(to: output)
    }

    static func imagesToPDF(_ images: [URL], output: URL) throws {
        let document = PDFDocument()
        for url in images {
            guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else { continue }
            document.insert(page, at: document.pageCount)
        }
        guard document.pageCount > 0 else { throw Failure.failed("没有可用的图片") }
        guard document.write(to: output) else { throw Failure.failed("PDF 写入失败") }
    }

    static func pdfText(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else { throw Failure.failed("无法读取 PDF") }
        // 每页独立处理：同一份 PDF 可能同时含有文字页与扫描页。
        var parts: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let text = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                parts.append(text)
            } else if let image = render(page: page, scale: 2),
                      let recognized = try? ocrText(image: image), !recognized.isEmpty {
                parts.append(recognized)
            }
        }
        guard !parts.isEmpty else { throw Failure.failed("未识别到文字（可能是空文件或扫描质量过低）") }
        return parts.joined(separator: "\n")
    }

    // MARK: - Vision OCR

    static func ocrText(imageURL: URL) throws -> String {
        guard let image = NSImage(contentsOf: imageURL) else {
            throw Failure.failed("无法读取图片")
        }
        return try ocrText(image: image)
    }

    static func ocrText(image: NSImage) throws -> String {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw Failure.failed("图片解码失败")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { throw Failure.failed("未识别到文字") }
        return lines.joined(separator: "\n")
    }

    private static func render(page: PDFPage, scale: CGFloat) -> NSImage? {
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: max(bounds.width * scale, 16), height: max(bounds.height * scale, 16))
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }
        image.unlockFocus()
        return image
    }

    // MARK: - 进程

    private struct ProcessResult {
        let status: Int32
        let error: String
    }

    private static func run(_ executable: String, _ arguments: [String],
                            timeout: TimeInterval,
                            environment: [String: String] = [:]) async throws -> ProcessResult {
        let process = Process()
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                throw Failure.failed("转换超时")
            }
            try await Task.sleep(nanoseconds: 120_000_000)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        return ProcessResult(status: process.terminationStatus, error: text)
    }
}


extension DocumentEngine {
    static func mergePDFs(_ urls: [URL], to output: URL) throws {
        let document = PDFDocument()
        for url in urls {
            guard let part = PDFDocument(url: url) else { continue }
            for index in 0..<part.pageCount {
                if let page = part.page(at: index) { document.insert(page, at: document.pageCount) }
            }
        }
        guard document.pageCount > 0 else { throw Failure.failed("没有可合并的页面") }
        guard document.write(to: output) else { throw Failure.failed("PDF 写入失败") }
    }

    static func splitPDF(_ url: URL, to directory: URL, every: Int) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw Failure.failed("无法读取 PDF") }
        let step = max(1, every)
        var files: [URL] = []
        var start = 0
        while start < document.pageCount {
            let part = PDFDocument()
            let end = min(start + step, document.pageCount)
            for index in start..<end {
                if let page = document.page(at: index) { part.insert(page, at: part.pageCount) }
            }
            let name = "\(url.deletingPathExtension().lastPathComponent)-\(start + 1)-\(end).pdf"
            let path = directory.appendingPathComponent(name)
            guard part.write(to: path) else { throw Failure.failed("拆分写入失败") }
            files.append(path)
            start = end
        }
        if files.count == 1 { return files[0] }
        let archive = directory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-split.zip")
        try zipFiles(files, to: archive)
        for file in files { try? FileManager.default.removeItem(at: file) }
        return archive
    }

    static func exportImages(_ url: URL, to directory: URL, format: String) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw Failure.failed("无法读取 PDF") }
        var files: [URL] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let image = render(page: page, scale: 2) else { continue }
            let tiff = image.tiffRepresentation
            let rep = tiff.flatMap { NSBitmapImageRep(data: $0) }
            let isPNG = format.lowercased() == "png"
            guard let data = rep?.representation(using: isPNG ? .png : .jpeg,
                                                 properties: isPNG ? [:] : [.compressionFactor: 0.9]) else { continue }
            let ext = isPNG ? "png" : "jpg"
            let path = directory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(index + 1).\(ext)")
            try data.write(to: path)
            files.append(path)
        }
        guard !files.isEmpty else { throw Failure.failed("没有可导出的页面") }
        let archive = directory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-images.zip")
        try zipFiles(files, to: archive)
        for file in files { try? FileManager.default.removeItem(at: file) }
        return archive
    }

    static func zipFiles(_ urls: [URL], to output: URL, level: Int = 6) throws {
        guard (0...9).contains(level), !urls.isEmpty else { throw Failure.failed("压缩级别必须为 0 到 9，且至少选择一个文件") }
        guard !urls.contains(where: { $0.standardizedFileURL == output.standardizedFileURL }) else {
            throw Failure.failed("压缩包不能覆盖输入文件")
        }
        guard Set(urls.map { $0.lastPathComponent }).count == urls.count else {
            throw Failure.failed("选择的文件存在相同文件名，请分别打包或重命名")
        }
        let temp = output.deletingLastPathComponent().appendingPathComponent(".anyconvert-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: temp) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-j", "-q", "-\(level)", temp.path] + urls.map(\.path)
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.failed("ZIP 打包失败") }
        if FileManager.default.fileExists(atPath: output.path) {
            _ = try FileManager.default.replaceItemAt(output, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: output)
        }
    }
}
