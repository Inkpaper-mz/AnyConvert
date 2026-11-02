import AppKit

func acLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["ANYCONVERT_DEBUG"] != nil else { return }
    let line = "[ac] \(message)\n"
    let url = URL(fileURLWithPath: "/tmp/ac_debug.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 强引用，避免 NSApplication.delegate（unowned）悬空
    static var retained: AppDelegate?

    private var window: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        L10n.bootstrap()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        let root = RootView(frame: NSRect(x: 0, y: 0, width: 1060, height: 720))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("app.title")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 960, height: 640)
        window.contentView = root
        window.center()
        window.setFrameAutosaveName("AnyConvertMainWindow")
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        self.window = window

        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        NSApp.activate(ignoringOtherApps: true)

        // 调试用：--focus-custom 自动聚焦第一个可编辑输入框（用于验证焦点环）
        if CommandLine.arguments.contains("--focus-custom") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                MainActor.assumeIsolated {
                    guard let root = self.window?.contentView else { return }
                    _ = self.focusFirstTextField(in: root)
                }
            }
        }

        // 调试用：--snapshot <png> 把窗口内容渲染成图片（不受遮挡影响）
        if let snapIndex = argsSnapshotIndex(), snapIndex + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[snapIndex + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + snapshotDelay()) {
                MainActor.assumeIsolated {
                    guard let view = self.window?.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    if let data = rep.representation(using: .png, properties: [:]) {
                        try? data.write(to: URL(fileURLWithPath: path))
                        acLog("snapshot -> \(path)")
                    }
                }
            }
        }

        // 调试用：--quit-after <秒> 自动退出（用于自动化截图）
        let args = CommandLine.arguments
        if let quitIndex = args.firstIndex(of: "--quit-after"), quitIndex + 1 < args.count,
           let seconds = Double(args[quitIndex + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
        }

        // 调试用：--preset <id> 启动时应用预设
        if let presetIndex = args.firstIndex(of: "--preset"), presetIndex + 1 < args.count,
           let preset = PresetStore.shared.preset(id: args[presetIndex + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                MainActor.assumeIsolated { AppModel.shared.apply(preset: preset) }
            }
        }

        // 调试用：--format <id> 启动时选中格式
        if let formatIndex = args.firstIndex(of: "--format"), formatIndex + 1 < args.count {
            let formatID = args[formatIndex + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated { AppModel.shared.setFormat(formatID) }
            }
        }

        // 调试用：--demo <文件...> [--autostart]
        if let demoIndex = args.firstIndex(of: "--demo") {
            let files = args[(demoIndex + 1)...].filter { !$0.hasPrefix("--") }
            let autostart = args.contains("--autostart")
            if !files.isEmpty {
                let urls = files.map { URL(fileURLWithPath: $0) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    MainActor.assumeIsolated { AppModel.shared.addFiles(urls) }
                }
                if autostart {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        MainActor.assumeIsolated { AppModel.shared.start() }
                    }
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Finder 右键 → 服务 →「用万能转码转换」
    @objc func convertWithAnyConvert(_ pboard: NSPasteboard,
                                     userData: String,
                                     error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else {
            error.pointee = L10n.t("msg.noMedia") as NSString
            return
        }
        AppModel.shared.addFiles(urls)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Finder 双击 / 打开方式
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard !filenames.isEmpty else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }
        AppModel.shared.addFiles(filenames.map { URL(fileURLWithPath: $0) })
        NSApp.activate(ignoringOtherApps: true)
        sender.reply(toOpenOrPrint: .success)
    }

    // MARK: - 菜单

    private func buildMainMenu() {
        let appName = L10n.t("app.title")
        let mainMenu = NSMenu()

        // 应用菜单
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()

        let aboutItem = NSMenuItem(title: L10n.t("menu.about", appName), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(NSMenuItem.separator())

        let languageItem = NSMenuItem(title: L10n.t("menu.language"), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu(title: L10n.t("menu.language"))
        for (index, language) in L10n.Language.allCases.enumerated() {
            let item = NSMenuItem(title: L10n.displayName(of: language),
                                  action: #selector(languageSelected(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            item.state = (L10n.preferred == language) ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        appMenu.addItem(languageItem)
        appMenu.addItem(NSMenuItem.separator())

        appMenu.addItem(withTitle: L10n.t("menu.hide", appName), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: L10n.t("menu.hideOthers"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: L10n.t("menu.showAll"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L10n.t("menu.quit", appName), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // 文件菜单
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: L10n.t("menu.file"))
        let addFiles = NSMenuItem(title: L10n.t("menu.addFiles"), action: #selector(addFiles), keyEquivalent: "o")
        addFiles.target = self
        fileMenu.addItem(addFiles)
        let addFolder = NSMenuItem(title: L10n.t("menu.addFolder"), action: #selector(addFolder), keyEquivalent: "o")
        addFolder.keyEquivalentModifierMask = [.command, .shift]
        addFolder.target = self
        fileMenu.addItem(addFolder)
        fileMenu.addItem(NSMenuItem.separator())
        let openOutput = NSMenuItem(title: L10n.t("menu.openOutput"), action: #selector(openOutputFolder), keyEquivalent: "r")
        openOutput.keyEquivalentModifierMask = [.command, .shift]
        openOutput.target = self
        fileMenu.addItem(openOutput)
        fileMenu.addItem(NSMenuItem.separator())
        let closeWindow = NSMenuItem(title: L10n.t("menu.closeWindow"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(closeWindow)
        fileItem.submenu = fileMenu

        // 编辑菜单
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: L10n.t("menu.edit"))
        editMenu.addItem(withTitle: L10n.t("menu.undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L10n.t("menu.redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: L10n.t("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.t("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.t("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.t("menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        // 转换菜单
        let convertItem = NSMenuItem()
        mainMenu.addItem(convertItem)
        let convertMenu = NSMenu(title: L10n.t("menu.convert"))
        let start = NSMenuItem(title: L10n.t("menu.start"), action: #selector(startConversion), keyEquivalent: "\r")
        start.target = self
        convertMenu.addItem(start)
        let cancel = NSMenuItem(title: L10n.t("menu.cancel"), action: #selector(cancelConversion), keyEquivalent: ".")
        cancel.target = self
        convertMenu.addItem(cancel)
        convertMenu.addItem(NSMenuItem.separator())
        let clear = NSMenuItem(title: L10n.t("menu.clearList"), action: #selector(clearList), keyEquivalent: "")
        clear.target = self
        convertMenu.addItem(clear)
        convertItem.submenu = convertMenu

        // 窗口菜单
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: L10n.t("menu.window"))
        windowMenu.addItem(withTitle: L10n.t("menu.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: L10n.t("menu.zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - 语言

    @objc private func languageSelected(_ sender: NSMenuItem) {
        let languages = L10n.Language.allCases
        guard sender.tag >= 0, sender.tag < languages.count else { return }
        LanguageSwitcher.apply(languages[sender.tag], window: window)
    }

    // MARK: - 其他

    private func focusFirstTextField(in view: NSView) -> Bool {
        for subview in view.subviews {
            if let field = subview as? NSTextField, field.isEditable, !field.isHidden, field.isEnabled {
                return view.window?.makeFirstResponder(field) ?? false
            }
            if focusFirstTextField(in: subview) { return true }
        }
        return false
    }

    private func argsSnapshotIndex() -> Int? {
        CommandLine.arguments.firstIndex(of: "--snapshot")
    }

    private func snapshotDelay() -> TimeInterval {
        guard let idx = CommandLine.arguments.firstIndex(of: "--snapshot-delay"),
              idx + 1 < CommandLine.arguments.count,
              let value = Double(CommandLine.arguments[idx + 1]) else { return 1.5 }
        return value
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = L10n.t("about.title")
        alert.informativeText = L10n.t("about.body")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.t("btn.ok"))
        alert.runModal()
    }

    @objc private func addFiles() { AppModel.shared.pickFiles() }
    @objc private func addFolder() { AppModel.shared.pickFolder() }
    @objc private func openOutputFolder() { AppModel.shared.openOutputFolder() }
    @objc private func startConversion() { AppModel.shared.start() }
    @objc private func cancelConversion() { AppModel.shared.cancel() }
    @objc private func clearList() { AppModel.shared.clearAll() }
}
