import AppKit
import PDFKit

/// PDF / ZIP 工具箱：合并、拆分、导出图片、图片转 PDF、打包 ZIP。
enum Toolbox {
    static func mergePDFs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let save = NSSavePanel()
        save.nameFieldStringValue = "merged.pdf"
        save.allowedContentTypes = [.pdf]
        guard save.runModal() == .OK, let output = save.url else { return }
        do {
            try DocumentEngine.mergePDFs(panel.urls, to: output)
            done("已合并 \(panel.urls.count) 个 PDF", output)
        } catch { fail(error) }
    }

    static func splitPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let input = panel.url else { return }
        let folder = NSOpenPanel()
        folder.canChooseFiles = false
        folder.canChooseDirectories = true
        guard folder.runModal() == .OK, let directory = folder.url else { return }
        do {
            let result = try DocumentEngine.splitPDF(input, to: directory, every: 1)
            done("已拆分", result)
        } catch { fail(error) }
    }

    static func exportPDFImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let input = panel.url else { return }
        let formatPicker = NSAlert()
        formatPicker.messageText = "选择页面图片格式"
        formatPicker.addButton(withTitle: "PNG")
        formatPicker.addButton(withTitle: "JPG")
        formatPicker.addButton(withTitle: "取消")
        let response = formatPicker.runModal()
        guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return }
        let format = response == .alertFirstButtonReturn ? "png" : "jpg"
        let folder = NSOpenPanel()
        folder.canChooseFiles = false
        folder.canChooseDirectories = true
        guard folder.runModal() == .OK, let directory = folder.url else { return }
        do {
            let result = try DocumentEngine.exportImages(input, to: directory, format: format)
            done("已导出页面", result)
        } catch { fail(error) }
    }

    static func pdfTablesToExcel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let input = panel.url else { return }
        let save = NSSavePanel()
        save.nameFieldStringValue = "tables.xlsx"
        guard save.runModal() == .OK, let output = save.url else { return }
        do {
            try PDFTableExtractor.export(from: input, to: output)
            done("已提取表格", output)
        } catch { fail(error) }
    }

    static func imagesToPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let save = NSSavePanel()
        save.nameFieldStringValue = "album.pdf"
        save.allowedContentTypes = [.pdf]
        guard save.runModal() == .OK, let output = save.url else { return }
        do {
            try DocumentEngine.imagesToPDF(panel.urls, output: output)
            done("已生成 PDF", output)
        } catch { fail(error) }
    }

    static func zipFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let options = NSAlert()
        options.messageText = "选择 ZIP 压缩级别"
        options.informativeText = "0 为仅打包，9 为最高压缩级别。"
        options.addButton(withTitle: "继续")
        options.addButton(withTitle: "取消")
        let levels = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 110, height: 26))
        levels.addItems(withTitles: (0...9).map(String.init))
        levels.selectItem(at: 6)
        options.accessoryView = levels
        guard options.runModal() == .alertFirstButtonReturn else { return }
        let level = levels.indexOfSelectedItem
        let save = NSSavePanel()
        save.nameFieldStringValue = "archive.zip"
        guard save.runModal() == .OK, let output = save.url else { return }
        do {
            let before = panel.urls.reduce(Int64(0)) { total, url in
                total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            try DocumentEngine.zipFiles(panel.urls, to: output, level: level)
            let after = Int64((try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            let formatter = ByteCountFormatter()
            done("已打包 \(panel.urls.count) 个文件（\(formatter.string(fromByteCount: before)) → \(formatter.string(fromByteCount: after))）", output)
        } catch { fail(error) }
    }

    private static func done(_ title: String, _ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = url.path
        alert.runModal()
    }

    private static func fail(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "操作失败"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
