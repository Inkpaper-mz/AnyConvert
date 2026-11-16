import Foundation
import CoreFoundation

enum StructuredText {
    static func convert(_ source: URL, target: String, output: URL) throws {
        let text = try String(contentsOf: source, encoding: .utf8)
        if source.pathExtension.lowercased() == "csv" && target == "json" {
            var rows = try parseCSV(text)
            guard !rows.isEmpty else { throw DocumentEngine.Failure.failed("CSV 文件为空") }
            var headers = rows.removeFirst()
            if !headers.isEmpty && headers[0].hasPrefix("\u{FEFF}") { headers[0].removeFirst() }
            guard headers.allSatisfy({ !$0.isEmpty }), Set(headers).count == headers.count else {
                throw DocumentEngine.Failure.failed("CSV 表头不能包含空列名或重复列名")
            }
            var objects: [[String: String]] = []
            for (index, row) in rows.enumerated() {
                guard row.count == headers.count else { throw DocumentEngine.Failure.failed("CSV 第 \(index + 2) 行列数与表头不同") }
                objects.append(Dictionary(uniqueKeysWithValues: zip(headers, row)))
            }
            let data = try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
            try data.write(to: output, options: .atomic)
        } else {
            let data = Data(text.utf8)
            guard let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], !objects.isEmpty else {
                throw DocumentEngine.Failure.failed("JSON 须为非空的对象数组，每个对象代表一行")
            }
            let keys = objects[0].keys.sorted()
            guard !keys.isEmpty, objects.allSatisfy({ Set($0.keys) == Set(keys) }) else {
                throw DocumentEngine.Failure.failed("JSON 各行必须有相同且非空的字段")
            }
            var rows = [keys.map(escape).joined(separator: ",")]
            for object in objects {
                let row = try keys.map { key -> String in
                    guard let value = object[key] else { throw DocumentEngine.Failure.failed("JSON 字段缺失") }
                    if let str = value as? String { return escape(str) }
                    if let num = value as? NSNumber {
                        if CFGetTypeID(num) == CFBooleanGetTypeID() { return num.boolValue ? "true" : "false" }
                        return num.stringValue
                    }
                    throw DocumentEngine.Failure.failed("CSV 不支持 JSON 中的嵌套对象、数组或 null")
                }
                rows.append(row.joined(separator: ","))
            }
            try (rows.joined(separator: "\r\n") + "\r\n").write(to: output, atomically: true, encoding: .utf8)
        }
    }

    /// 仅转换单一、无合并单元格的表格；拒绝丢失正文或链接等附加信息。
    static func tableASTToCSV(_ data: Data, output: URL) throws {
        func invalid(_ message: String) -> DocumentEngine.Failure { .failed(message) }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = root["blocks"] as? [[String: Any]], blocks.count == 1,
              blocks[0]["t"] as? String == "Table", let table = blocks[0]["c"] as? [Any], table.count == 6,
              let head = table[3] as? [Any], head.count == 2, let headerRows = head[1] as? [Any], headerRows.count == 1,
              let bodies = table[4] as? [Any] else { throw invalid("只能转换仅包含一个带表头的表格，其他正文请先另存") }
        guard let caption = table[1] as? [Any], caption.count == 2, caption[0] is NSNull,
              let captionBlocks = caption[1] as? [Any], captionBlocks.isEmpty else { throw invalid("表格含有标题，无法无损转为 CSV") }
        func inline(_ nodes: [[String: Any]]) throws -> String {
            var text = ""
            for node in nodes {
                let kind = node["t"] as? String ?? ""
                switch kind {
                case "Str": text += node["c"] as? String ?? ""
                case "Space": text += " "
                case "SoftBreak", "LineBreak": text += "\n"
                case "Emph", "Strong", "Strikeout":
                    guard let children = node["c"] as? [[String: Any]] else { throw invalid("表格格式无法转换") }
                    text += try inline(children)
                case "Code":
                    guard let code = node["c"] as? [Any], code.count == 2, let value = code[1] as? String else { throw invalid("表格代码无法转换") }
                    text += value
                default: throw invalid("表格中含有链接、图片或不支持的内容")
                }
            }
            return text
        }
        func parseRow(_ value: Any) throws -> [String] {
            guard let row = value as? [Any], row.count == 2, let cells = row[1] as? [Any] else { throw invalid("表格行格式不支持") }
            return try cells.map { item in
                guard let cell = item as? [Any], cell.count == 5,
                      let rowSpan = cell[2] as? Int, let colSpan = cell[3] as? Int,
                      rowSpan == 1, colSpan == 1, let blocks = cell[4] as? [[String: Any]], blocks.count <= 1 else {
                    throw invalid("不支持合并单元格或多段落单元格")
                }
                guard let block = blocks.first else { return "" }
                guard ["Plain", "Para"].contains(block["t"] as? String ?? ""), let nodes = block["c"] as? [[String: Any]] else { throw invalid("单元格内容无法转换") }
                return try inline(nodes)
            }
        }
        let header = try parseRow(headerRows[0])
        guard !header.isEmpty, header.allSatisfy({ !$0.isEmpty }), Set(header).count == header.count else { throw invalid("表头不能有空白或重复列名") }
        var rows = [header]
        for item in bodies {
            guard let body = item as? [Any], body.count == 4, let headerPart = body[2] as? [Any], headerPart.isEmpty,
                  let bodyRows = body[3] as? [Any] else { throw invalid("不支持多级表头") }
            for value in bodyRows { let row = try parseRow(value); guard row.count == header.count else { throw invalid("表格各行列数不一致") }; rows.append(row) }
        }
        guard let foot = table[5] as? [Any], foot.count == 2, let footerRows = foot[1] as? [Any], footerRows.isEmpty else { throw invalid("不支持表尾") }
        let csv = rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        try csv.write(to: output, atomically: true, encoding: .utf8)
    }

    private static func escape(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    private static func parseCSV(_ text: String) throws -> [[String]] {
        let chars = Array(text); var i = 0; var rows: [[String]] = []; var row: [String] = []; var field = ""
        var quoted = false; var closed = false; var hasRecord = false
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == "," {
                row.append(field); field = ""; closed = false; hasRecord = true
            } else if c == "\n" || c == "\r" || c == "\r\n" {
                row.append(field); rows.append(row); row = []; field = ""; closed = false; hasRecord = false
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
            } else if c == "\"" {
                guard field.isEmpty && !closed else { throw DocumentEngine.Failure.failed("CSV 引号格式不正确") }
                quoted = true; hasRecord = true
            } else {
                guard !closed else { throw DocumentEngine.Failure.failed("CSV 引号后存在无效字符") }
                field.append(c); hasRecord = true
            }
            i += 1
        }
        guard !quoted else { throw DocumentEngine.Failure.failed("CSV 存在未闭合引号") }
        if hasRecord || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
