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
        "xls", "xlsx", "ods", "et", "csv", "ppt", "pptx", "odp", "dps", "dpt",
    ]
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "avif", "tiff", "tif", "bmp", "ico", "heic", "heif",
    ]

    /// 目标 → 允许的源格式（与跨平台矩阵保持一致的核心子集）
    static let matrix: [String: Set<String>] = [
        "pdf": documentExtensions.union(imageExtensions).union(["epub"]),
        "docx": ["doc", "wps", "odt", "rtf", "txt", "md", "html", "htm", "pdf"],
        "odt": ["doc", "docx", "wps", "rtf", "txt", "md", "html", "htm", "pdf"],
        "rtf": ["doc", "docx", "wps", "odt", "txt", "md", "html", "htm", "pdf"],
        "txt": ["doc", "docx", "wps", "odt", "rtf", "pdf", "md", "html", "htm", "csv", "xlsx"],
        "html": ["doc", "docx", "wps", "odt", "rtf", "txt", "md", "pdf"],
        "xlsx": ["xls", "ods", "et", "csv", "tsv"],
        "csv": ["xls", "xlsx", "ods", "et", "tsv"],
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

        if ext == "pdf" {
            if isImage(sourceExt) {
                try imagesToPDF([src], output: output)
                progress(1)
                return
            }
            try await libreOfficeConvert(src: src, ext: ext, output: output)
            progress(1)
            return
        }

        if ext == "txt", isImage(sourceExt) {
            let text = try ocrText(imageURL: src)
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
        let args = [
            "--headless", "--norestore", "--nolockcheck", "--nodefault",
            "-env:UserInstallation=file://\(profile.path)",
            "--convert-to", ext, "--outdir", work.path, src.path,
        ]
        let result = try await run(soffice.path, args, timeout: 300)
        try? FileManager.default.removeItem(at: profile)
        guard result.status == 0 else {
            throw Failure.failed(result.error.isEmpty ? "LibreOffice 转换失败" : result.error)
        }
        let produced = (try? FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension.lowercased() == ext }
        guard let produced else {
            throw Failure.failed(result.error.isEmpty ? "LibreOffice 没有生成输出" : result.error)
        }
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.moveItem(at: produced, to: output)
    }

    // MARK: - PDFKit

    static func renderPDF(src: URL, ext: String, output: URL) throws {
        guard let document = PDFDocument(url: src), let page = document.page(at: 0) else {
            throw Failure.failed("无法读取 PDF")
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
        let text = (document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        // 扫描件：逐页渲染后走 Vision
        var parts: [String] = []
        for index in 0..<document.pageCount {
            if let page = document.page(at: index),
               let image = render(page: page, scale: 2),
               let text = try? ocrText(image: image), !text.isEmpty {
                parts.append(text)
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
                            timeout: TimeInterval) async throws -> ProcessResult {
        let process = Process()
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

    static func zipFiles(_ urls: [URL], to output: URL) throws {
        try? FileManager.default.removeItem(at: output)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-j", "-q", output.path] + urls.map(\.path)
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.failed("ZIP 打包失败") }
    }
}
