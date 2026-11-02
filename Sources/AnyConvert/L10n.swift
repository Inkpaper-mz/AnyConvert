import Foundation

/// 轻量本地化：6 种语言，字符串表在 Resources/Strings.json。
enum L10n {
    enum Language: String, CaseIterable {
        case system
        case zhHans = "zh-Hans"
        case zhHant = "zh-Hant"
        case en
        case ja
        case ko
        case fr

        var displayNameKey: String {
            switch self {
            case .system: return "lang.system"
            case .zhHans: return "lang.zhHans"
            case .zhHant: return "lang.zhHant"
            case .en: return "lang.en"
            case .ja: return "lang.ja"
            case .ko: return "lang.ko"
            case .fr: return "lang.fr"
            }
        }

        /// 用于菜单选择，避免 system 显示成具体语言名
        var isSystem: Bool { self == .system }
    }

    private static var table: [String: [String: String]] = [:]
    private static var resolved: Language = .zhHans
    private(set) static var current: Language = .system

    static let defaultsKey = "ac.language"

    // MARK: - 启动

    static func bootstrap() {
        loadTable()
        current = resolvePreference()
        resolved = current == .system ? detectSystemLanguage() : current
        if table[resolved.rawValue] == nil {
            resolved = table["en"] != nil ? .en : .zhHans
        }
    }

    static var preferred: Language { current }

    static var systemLanguage: Language { detectSystemLanguage() }

    private static func resolvePreference() -> Language {
        if let forced = ProcessInfo.processInfo.environment["ANYCONVERT_LANG"],
           let lang = Language(rawValue: forced) {
            return lang
        }
        if let stored = UserDefaults.standard.string(forKey: defaultsKey),
           let lang = Language(rawValue: stored) {
            return lang
        }
        return .system
    }

    static func setLanguage(_ language: Language) {
        UserDefaults.standard.set(language.rawValue, forKey: defaultsKey)
    }

    private static func detectSystemLanguage() -> Language {
        for identifier in Locale.preferredLanguages {
            let value = identifier.lowercased()
            if value.hasPrefix("zh") {
                if value.contains("hant") || value.contains("tw") || value.contains("hk") || value.contains("mo") {
                    return .zhHant
                }
                return .zhHans
            }
            if value.hasPrefix("ja") { return .ja }
            if value.hasPrefix("ko") { return .ko }
            if value.hasPrefix("fr") { return .fr }
            if value.hasPrefix("en") { return .en }
        }
        return .en
    }

    // MARK: - 查表

    private static func loadTable() {
        for url in candidateURLs() {
            if let data = try? Data(contentsOf: url),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] {
                table = object
                return
            }
        }
        table = [:]
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []
        if let url = Bundle.main.url(forResource: "Strings", withExtension: "json") {
            urls.append(url)
        }
        if let dir = ProcessInfo.processInfo.environment["ANYCONVERT_RESOURCES"] {
            urls.append(URL(fileURLWithPath: dir).appendingPathComponent("Strings.json"))
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        urls.append(cwd.appendingPathComponent("Resources/Strings.json"))
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            urls.append(exeDir.appendingPathComponent("../Resources/Strings.json").standardizedFileURL)
            urls.append(exeDir.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources/Strings.json").standardizedFileURL)
        }
        return urls
    }

    static func t(_ key: String) -> String {
        if let value = table[resolved.rawValue]?[key], !value.isEmpty { return value }
        if let value = table["en"]?[key], !value.isEmpty { return value }
        if let value = table["zh-Hans"]?[key], !value.isEmpty { return value }
        return key
    }

    static func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), arguments: arguments)
    }

    /// 某个语言下的名字（语言菜单用，永远显示该语言自己的写法）
    static func displayName(of language: Language) -> String {
        if language == .system {
            return t("lang.system")
        }
        guard let value = table[language.rawValue]?[language.displayNameKey], !value.isEmpty else {
            return language.rawValue
        }
        return value
    }
}
