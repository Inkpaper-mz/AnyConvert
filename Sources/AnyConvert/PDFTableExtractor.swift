import AppKit
import PDFKit
import Vision

/// PDF 表格 → XLSX：逐页渲染 + Vision 识别文字坐标，按行聚类、按横向间距分列，写成标准 xlsx。
enum PDFTableExtractor {
    enum Failure: LocalizedError {
        case open, noText, write
        var errorDescription: String? {
            switch self {
            case .open: return "无法读取 PDF"
            case .noText: return "未识别到表格文字（扫描件请确认清晰度）"
            case .write: return "xlsx 写入失败"
            }
        }
    }

    private struct Token {
        let text: String
        let rect: CGRect
    }

    static func export(from source: URL, to output: URL) throws {
        guard let document = PDFDocument(url: source) else { throw Failure.open }
        var rows: [[String]] = []

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let textRows = textLayerRows(page)
            let pageRows = textRows.contains(where: { $0.count > 1 }) ? textRows : (try ocrRows(page))
            rows.append(contentsOf: pageRows)
            if index < document.pageCount - 1, !rows.isEmpty { rows.append([]) }
        }

        if ProcessInfo.processInfo.environment["ANYCONVERT_DEBUG_TABLES"] != nil {
            for row in rows { print("ROW:", row) }
        }
        guard !rows.isEmpty else { throw Failure.noText }
        try writeXLSX(rows: rows, to: output)
    }

    // MARK: - 文本层（按选区探测列）

    private static func textLayerRows(_ page: PDFPage) -> [[String]] {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0,
              let all = page.selection(for: bounds) else { return [] }

        var rows: [[String]] = []
        for line in all.selectionsByLine() {
            let rect = line.bounds(for: page)
            guard rect.width > 4, rect.height > 2 else { continue }
            let slices = 160
            let step = rect.width / CGFloat(slices)
            var runs: [(CGFloat, CGFloat)] = []
            var start: CGFloat?
            for index in 0..<slices {
                let x = rect.minX + CGFloat(index) * step
                let slice = CGRect(x: x, y: rect.minY, width: step * 0.98, height: rect.height)
                let text = page.selection(for: slice)?.string ?? ""
                let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if hasText, start == nil { start = x }
                if !hasText, let begin = start {
                    runs.append((begin, x))
                    start = nil
                }
            }
            if let begin = start { runs.append((begin, rect.maxX)) }
            guard !runs.isEmpty else { continue }

            var cells: [String] = []
            var current: CGRect?
            let cellGap = bounds.width * 0.015
            for run in runs {
                let runRect = CGRect(x: run.0, y: rect.minY, width: run.1 - run.0, height: rect.height)
                if let existing = current, runRect.minX - existing.maxX > cellGap {
                    let text = (page.selection(for: existing)?.string ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { cells.append(text) }
                    current = runRect
                } else {
                    current = current?.union(runRect) ?? runRect
                }
            }
            if let existing = current {
                let text = (page.selection(for: existing)?.string ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { cells.append(text) }
            }
            if !cells.isEmpty { rows.append(cells) }
        }
        return rows
    }

    // MARK: - OCR（扫描件）

    private static func ocrRows(_ page: PDFPage) throws -> [[String]] {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 4
        let size = CGSize(width: max(bounds.width * scale, 32), height: max(bounds.height * scale, 32))
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

        if ProcessInfo.processInfo.environment["ANYCONVERT_DEBUG_TABLES"] != nil {
            if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "/tmp/table_render.png"))
            }
        }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "zh-Hans"]
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

        var tokens: [Token] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            if ProcessInfo.processInfo.environment["ANYCONVERT_DEBUG_TABLES"] != nil {
                print("OBS:", candidate.string, observation.boundingBox)
            }
            tokens.append(Token(text: candidate.string, rect: observation.boundingBox))
        }
        return buildRows(tokens, mergeGap: 0)
    }

    /// 先按 y 聚类成行，再按横向间距切列。
    private static func buildRows(_ tokens: [Token], mergeGap: CGFloat) -> [[String]] {
        guard !tokens.isEmpty else { return [] }
        let sorted = tokens.sorted { $0.rect.midY > $1.rect.midY }
        var lines: [[Token]] = []
        for token in sorted {
            if var last = lines.last, let anchor = last.first,
               abs(anchor.rect.midY - token.rect.midY) < 0.012 {
                last.append(token)
                lines[lines.count - 1] = last
            } else {
                lines.append([token])
            }
        }

        return lines.map { line in
            let ordered = line.sorted { $0.rect.minX < $1.rect.minX }
            var words: [(String, CGRect)] = []
            for token in ordered {
                if var last = words.last, mergeGap > 0,
                   token.rect.minX - last.1.maxX <= mergeGap {
                    last.0 += token.text
                    last.1 = last.1.union(token.rect)
                    words[words.count - 1] = last
                } else {
                    words.append((token.text, token.rect))
                }
            }
            var cells: [String] = []
            var current = ""
            var lastMaxX: CGFloat = -.infinity
            for (text, rect) in words {
                if !current.isEmpty, rect.minX - lastMaxX > 0.02 {
                    cells.append(current)
                    current = text
                } else {
                    current += current.isEmpty ? text : " " + text
                }
                lastMaxX = max(lastMaxX, rect.maxX)
            }
            if !current.isEmpty { cells.append(current) }
            return cells
        }
    }

    // MARK: - 最小 XLSX 写入

    private static func columnName(_ index: Int) -> String {
        var value = index + 1
        var result = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            result = String(UnicodeScalar(65 + remainder)!) + result
            value = (value - 1) / 26
        }
        return result
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func writeXLSX(rows: [[String]], to output: URL) throws {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("anyconvert-xlsx-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="Tables" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """
        let workbookRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """

        var sheet = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>"#
        for (rowIndex, row) in rows.enumerated() {
            sheet += "<row r=\"\(rowIndex + 1)\">"
            for (column, value) in row.enumerated() {
                let ref = "\(columnName(column))\(rowIndex + 1)"
                let number = Double(value)
                if let number, value.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil {
                    sheet += "<c r=\"\(ref)\"><v>\(number)</v></c>"
                } else {
                    sheet += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(value))</t></is></c>"
                }
            }
            sheet += "</row>"
        }
        sheet += "</sheetData></worksheet>"

        let files: [(String, String)] = [
            ("[Content_Types].xml", contentTypes),
            ("_rels/.rels", rels),
            ("xl/workbook.xml", workbook),
            ("xl/_rels/workbook.xml.rels", workbookRels),
            ("xl/worksheets/sheet1.xml", sheet),
        ]
        for (path, content) in files {
            let target = work.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.data(using: .utf8)?.write(to: target)
        }

        try? FileManager.default.removeItem(at: output)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", output.path, "[Content_Types].xml", "_rels", "xl"]
        process.currentDirectoryURL = work
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.write }
    }
}
