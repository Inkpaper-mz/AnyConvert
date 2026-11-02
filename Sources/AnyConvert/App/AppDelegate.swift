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
        acLog("willFinishLaunching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        acLog("didFinishLaunching")
        buildMainMenu()
        acLog("menu built")

        acLog("before RootView")
        let root = RootView(frame: NSRect(x: 0, y: 0, width: 1060, height: 720))
        acLog("after RootView")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        acLog("window created")
        window.title = "万能转码"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 960, height: 640)
        window.contentView = root
        window.center()
        window.setFrameAutosaveName("AnyConvertMainWindow")
        acLog("window frame before show: \(window.frame) screen=\(String(describing: window.screen?.frame))")
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        self.window = window

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

        // 调试用：--demo <文件...> [--autostart]
        let args = CommandLine.arguments
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
        acLog("after show: visible=\(window.isVisible) key=\(window.isKeyWindow) windows=\(NSApp.windows.count) frame=\(window.frame)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - 菜单

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // 应用菜单
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 万能转码", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "隐藏 万能转码", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        appMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 万能转码", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in appMenu.items where item.action == #selector(showAbout) {
            item.target = self
        }
        appMenuItem.submenu = appMenu

        // 文件菜单
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(withTitle: "添加文件…", action: #selector(addFiles), keyEquivalent: "o")
        let addFolder = NSMenuItem(title: "添加文件夹…", action: #selector(addFolder), keyEquivalent: "o")
        addFolder.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(addFolder)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "在 Finder 中打开输出文件夹", action: #selector(openOutputFolder), keyEquivalent: "r")
        fileMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        for item in fileMenu.items where item.target == nil && item.action != #selector(NSWindow.performClose(_:)) {
            item.target = self
        }
        fileItem.submenu = fileMenu

        // 编辑菜单
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        // 转换菜单
        let convertItem = NSMenuItem()
        mainMenu.addItem(convertItem)
        let convertMenu = NSMenu(title: "转换")
        convertMenu.addItem(withTitle: "开始转换", action: #selector(startConversion), keyEquivalent: "\r")
        convertMenu.addItem(withTitle: "取消转换", action: #selector(cancelConversion), keyEquivalent: ".")
        convertMenu.addItem(NSMenuItem.separator())
        convertMenu.addItem(withTitle: "清空列表", action: #selector(clearList), keyEquivalent: "")
        for item in convertMenu.items where item.action != nil {
            item.target = self
        }
        convertItem.submenu = convertMenu

        // 窗口菜单
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

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
        alert.messageText = "万能转码 1.0"
        alert.informativeText = """
        基于 FFmpeg 的视频 / 音频格式转换工具，支持 25 种输出格式与几乎所有输入格式。

        交互界面：MIT License
        转码引擎：FFmpeg（GPL v3）
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func addFiles() { AppModel.shared.pickFiles() }
    @objc private func addFolder() { AppModel.shared.pickFolder() }
    @objc private func openOutputFolder() { AppModel.shared.openOutputFolder() }
    @objc private func startConversion() { AppModel.shared.start() }
    @objc private func cancelConversion() { AppModel.shared.cancel() }
    @objc private func clearList() { AppModel.shared.clearAll() }
}
