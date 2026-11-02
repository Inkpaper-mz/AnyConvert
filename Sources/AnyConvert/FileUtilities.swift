import AppKit
import Foundation

/// 目录扫描 + 文件名/输出路径工具。
enum FileUtilities {
    /// 可识别的媒体扩展名（用于展开文件夹；拖拽则不做限制）
    static let mediaExtensions: Set<String> = [
        // 视频
        "mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv", "flv", "f4v", "ts", "m2ts", "mts",
        "mpg", "mpeg", "m2v", "m1v", "vob", "3gp", "3g2", "ogv", "rm", "rmvb", "asf", "divx",
        "mxf", "dv", "wtv", "dvr-ms", "gif",
        // 音频
        "mp3", "wav", "flac", "aac", "m4a", "m4b", "ogg", "oga", "opus", "wma", "aiff", "aif",
        "aifc", "ac3", "eac3", "dts", "caf", "amr", "au", "ape", "wv", "tta", "mka", "mp2", "mpa",
    ]

    static func isMediaFile(_ url: URL) -> Bool {
        mediaExtensions.contains(url.pathExtension.lowercased())
    }

    /// 递归展开文件夹（跳过隐藏目录与 .app 包），返回媒体文件
    static func expand(urls: [URL], limit: Int = 800) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default

        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            if !isDirectory.boolValue {
                result.append(url)
                continue
            }

            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: nil
            ) else { continue }

            for case let file as URL in enumerator {
                if result.count >= limit { break }
                guard isMediaFile(file) else { continue }
                let values = try? file.resourceValues(forKeys: [.isRegularFileKey])
                if values?.isRegularFile == true { result.append(file) }
            }
        }
        return result
    }

    /// 生成不冲突的输出路径
    static func outputURL(for input: URL, ext: String, directory: URL, inUse: Set<URL> = []) -> URL {
        let base = input.deletingPathExtension().lastPathComponent
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var index = 1
        while fm.fileExists(atPath: candidate.path) || inUse.contains(candidate) || candidate == input {
            candidate = directory.appendingPathComponent("\(base) (\(index))").appendingPathExtension(ext)
            index += 1
            if index > 999 { break }
        }
        return candidate
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
