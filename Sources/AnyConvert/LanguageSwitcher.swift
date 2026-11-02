import AppKit

/// 语言切换的共用流程：写入偏好 → 提示重启 → 重新拉起 App。
@MainActor
enum LanguageSwitcher {
    static func apply(_ language: L10n.Language, window: NSWindow?) {
        guard language != L10n.preferred else { return }
        L10n.setLanguage(language)

        let alert = NSAlert()
        alert.messageText = L10n.t("lang.restartTitle")
        alert.informativeText = L10n.t("lang.restartBody")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.t("btn.restart"))
        alert.addButton(withTitle: L10n.t("btn.later"))

        if alert.runModal() == .alertFirstButtonReturn {
            relaunch()
        }
    }

    static func relaunch() {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else {
            NSApp.terminate(nil)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
