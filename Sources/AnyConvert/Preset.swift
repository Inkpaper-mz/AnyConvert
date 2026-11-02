import Foundation

/// 转换预设：一组「目标格式 + 画质 + 分辨率 + 码率 + 额外参数」的快照。
/// 参考 File Converter 的 ConversionPreset / ConversionPresetTemplates。
struct ConversionPreset: Codable, Identifiable, Equatable {

    var id: String
    var nameKey: String?        // 内置预设的本地化 key
    var name: String?           // 自定义预设的名称
    var formatID: String
    var quality: Quality
    var resolution: ResolutionPreset
    var bitrate: AudioBitrate
    var hardware: Bool
    var customWidth: Int?
    var customHeight: Int?
    var extraArguments: [String]
    var isBuiltin: Bool

    var displayName: String {
        if let nameKey { return L10n.t(nameKey) }
        return name ?? L10n.t("preset.custom")
    }

    var format: OutputFormat { Catalog.format(formatID) }
}

enum PresetCatalog {
    static let builtins: [ConversionPreset] = [
        ConversionPreset(id: "builtin.wechat", nameKey: "preset.wechat", name: nil,
                         formatID: "mp4", quality: .small, resolution: .hd720, bitrate: .b128,
                         hardware: false, customWidth: nil, customHeight: nil,
                         extraArguments: [], isBuiltin: true),
        ConversionPreset(id: "builtin.archive", nameKey: "preset.archive", name: nil,
                         formatID: "mp4", quality: .high, resolution: .original, bitrate: .b320,
                         hardware: false, customWidth: nil, customHeight: nil,
                         extraArguments: [], isBuiltin: true),
        ConversionPreset(id: "builtin.audio", nameKey: "preset.audio", name: nil,
                         formatID: "mp3", quality: .balanced, resolution: .original, bitrate: .b192,
                         hardware: false, customWidth: nil, customHeight: nil,
                         extraArguments: [], isBuiltin: true),
        ConversionPreset(id: "builtin.gif", nameKey: "preset.gif", name: nil,
                         formatID: "gif", quality: .small, resolution: .sd360, bitrate: .b128,
                         hardware: false, customWidth: nil, customHeight: nil,
                         extraArguments: [], isBuiltin: true),
        ConversionPreset(id: "builtin.webm", nameKey: "preset.webm", name: nil,
                         formatID: "webm", quality: .balanced, resolution: .fhd1080, bitrate: .b192,
                         hardware: false, customWidth: nil, customHeight: nil,
                         extraArguments: [], isBuiltin: true),
        ConversionPreset(id: "builtin.podcast", nameKey: "preset.podcast", name: nil,
                         formatID: "m4a", quality: .balanced, resolution: .original, bitrate: .b128,
                         hardware: false, customWidth: nil, customHeight: nil,
                         extraArguments: [], isBuiltin: true),
    ]
}

/// 预设存储：内置固定，自定义存 UserDefaults
final class PresetStore {
    static let shared = PresetStore()

    private let key = "ac.presets"
    private(set) var custom: [ConversionPreset] = []

    private init() { load() }

    var all: [ConversionPreset] { PresetCatalog.builtins + custom }

    func preset(id: String) -> ConversionPreset? {
        all.first { $0.id == id }
    }

    func add(name: String, from settings: ConversionSettings) -> ConversionPreset {
        let preset = ConversionPreset(
            id: "custom.\(UUID().uuidString.prefix(8))",
            nameKey: nil,
            name: name,
            formatID: settings.format.id,
            quality: settings.quality,
            resolution: settings.resolution,
            bitrate: settings.audioBitrate,
            hardware: settings.hardware,
            customWidth: settings.customWidth,
            customHeight: settings.customHeight,
            extraArguments: settings.extraArguments,
            isBuiltin: false
        )
        custom.append(preset)
        save()
        return preset
    }

    func remove(id: String) {
        custom.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([ConversionPreset].self, from: data) else { return }
        custom = list
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(custom) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
