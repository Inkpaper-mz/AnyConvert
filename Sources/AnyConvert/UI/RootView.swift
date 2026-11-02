import AppKit

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 主窗口内容
final class RootView: NSView, AppModelObserver {
    private let model = AppModel.shared

    private let header = NSView()
    private let contentArea = NSView()
    private let footer = NSView()

    private let dropZone = DropZoneView()
    private let listScroll = NSScrollView()
    private let listStack = NSStackView()
    private let settingsScroll = NSScrollView()
    private let settingsPanel = SettingsPanel()

    private let startButton = GradientButton(title: L10n.t("btn.start"), symbol: "bolt.fill", large: true)
    private let cancelButton = PillButton(title: L10n.t("btn.cancel"))
    private let clearButton = PillButton(title: L10n.t("btn.clear"))
    private let clearDoneButton = PillButton(title: L10n.t("btn.clearDone"))
    private let summaryLabel = Label.make("", size: 11, color: .secondaryLabelColor)
    private let ffmpegBadge = BadgeView(text: "检测中…", tone: .neutral)
    private let folderButton = NSButton()
    private let dropHint = Label.make("", size: 11, color: .secondaryLabelColor)
    private var rows: [UUID: JobRowView] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        acLog("RootView header…")
        buildHeader()
        acLog("RootView content…")
        buildContent()
        acLog("RootView footer…")
        buildFooter()
        acLog("RootView chrome done")

        registerForDraggedTypes([.fileURL])
        model.observer = self
        model.bootstrap()
        acLog("RootView bootstrap done")

        dropZone.onPickFiles = { [weak self] in self?.model.pickFiles() }
        dropZone.onPickFolder = { [weak self] in self?.model.pickFolder() }

        reloadAll()
        acLog("RootView reload done")
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: - 布局骨架

    private func buildHeader() {
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        let icon = IconTile(symbol: "arrow.triangle.2.circlepath", colors: [Theme.accent, Theme.accentDeep], size: 34)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolName = "arrow.triangle.2.circlepath"

        let title = Label.make(L10n.t("app.title"), size: 16, weight: .semibold)
        title.setContentHuggingPriority(.required, for: .horizontal)
        let subtitle = Label.make(L10n.t("app.tagline"),
                                  size: 11, color: .secondaryLabelColor)
        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        folderButton.image = Symbols.image("folder", size: 13, weight: .regular)
        folderButton.isBordered = false
        folderButton.bezelStyle = .regularSquare
        folderButton.target = self
        folderButton.action = #selector(openOutputFolder)
        folderButton.toolTip = L10n.t("menu.openOutput")
        folderButton.translatesAutoresizingMaskIntoConstraints = false
        folderButton.setContentHuggingPriority(.required, for: .horizontal)

        header.addSubview(icon)
        header.addSubview(titleStack)
        header.addSubview(spacer)
        header.addSubview(ffmpegBadge)
        header.addSubview(folderButton)
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        ffmpegBadge.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 84),

            icon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: header.centerYAnchor, constant: 12),

            titleStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 11),
            titleStack.centerYAnchor.constraint(equalTo: header.centerYAnchor, constant: 12),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: ffmpegBadge.leadingAnchor, constant: -12),

            ffmpegBadge.trailingAnchor.constraint(equalTo: folderButton.leadingAnchor, constant: -10),
            ffmpegBadge.centerYAnchor.constraint(equalTo: header.centerYAnchor, constant: 12),

            folderButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -18),
            folderButton.centerYAnchor.constraint(equalTo: header.centerYAnchor, constant: 12),
            folderButton.widthAnchor.constraint(equalToConstant: 24),
            folderButton.heightAnchor.constraint(equalToConstant: 22),
        ])

        let hairline = HairlineView()
        header.addSubview(hairline)
        hairline.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hairline.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func buildContent() {
        contentArea.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentArea)

        // 左栏
        let left = NSView()
        left.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(left)

        dropZone.translatesAutoresizingMaskIntoConstraints = false
        left.addSubview(dropZone)

        listScroll.translatesAutoresizingMaskIntoConstraints = false
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true
        listScroll.scrollerStyle = .overlay
        left.addSubview(listScroll)

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 8
        listStack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 10, right: 0)
        doc.addSubview(listStack)
        listScroll.documentView = doc

        NSLayoutConstraint.activate([
            listStack.topAnchor.constraint(equalTo: doc.topAnchor),
            listStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            listStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.widthAnchor.constraint(equalTo: listScroll.contentView.widthAnchor),
            doc.topAnchor.constraint(equalTo: listScroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: listScroll.contentView.leadingAnchor),
        ])

        NSLayoutConstraint.activate([
            dropZone.topAnchor.constraint(equalTo: left.topAnchor),
            dropZone.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            dropZone.trailingAnchor.constraint(equalTo: left.trailingAnchor),

            listScroll.topAnchor.constraint(equalTo: dropZone.bottomAnchor, constant: 12),
            listScroll.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            listScroll.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            listScroll.bottomAnchor.constraint(equalTo: left.bottomAnchor),
        ])

        // 分隔 + 右栏
        let verticalLine = HairlineView()
        verticalLine.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(verticalLine)

        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = Theme.sidebarFill.cgColor
        contentArea.addSubview(sidebar)

        settingsScroll.translatesAutoresizingMaskIntoConstraints = false
        settingsScroll.drawsBackground = false
        settingsScroll.hasVerticalScroller = true
        settingsScroll.autohidesScrollers = true
        sidebar.addSubview(settingsScroll)

        let settingsDoc = FlippedView()
        settingsDoc.translatesAutoresizingMaskIntoConstraints = false
        settingsPanel.translatesAutoresizingMaskIntoConstraints = false
        settingsDoc.addSubview(settingsPanel)
        settingsScroll.documentView = settingsDoc

        NSLayoutConstraint.activate([
            settingsPanel.topAnchor.constraint(equalTo: settingsDoc.topAnchor),
            settingsPanel.leadingAnchor.constraint(equalTo: settingsDoc.leadingAnchor, constant: 6),
            settingsPanel.trailingAnchor.constraint(equalTo: settingsDoc.trailingAnchor, constant: -6),
            settingsPanel.bottomAnchor.constraint(equalTo: settingsDoc.bottomAnchor),
            settingsDoc.widthAnchor.constraint(equalTo: settingsScroll.contentView.widthAnchor),
            settingsDoc.topAnchor.constraint(equalTo: settingsScroll.contentView.topAnchor),
            settingsDoc.leadingAnchor.constraint(equalTo: settingsScroll.contentView.leadingAnchor),

            settingsScroll.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 18),
            settingsScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            settingsScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18),
            settingsScroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -18),
        ])

        NSLayoutConstraint.activate([
            contentArea.topAnchor.constraint(equalTo: header.bottomAnchor),
            contentArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: trailingAnchor),

            left.topAnchor.constraint(equalTo: contentArea.topAnchor, constant: 18),
            left.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor, constant: 18),
            left.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor, constant: -18),

            verticalLine.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 18),
            verticalLine.topAnchor.constraint(equalTo: contentArea.topAnchor),
            verticalLine.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            verticalLine.widthAnchor.constraint(equalToConstant: 1),

            sidebar.leadingAnchor.constraint(equalTo: verticalLine.trailingAnchor),
            sidebar.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            sidebar.topAnchor.constraint(equalTo: contentArea.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 300),
        ])
    }

    private func buildFooter() {
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.wantsLayer = true
        footer.layer?.backgroundColor = Theme.sidebarFill.cgColor
        addSubview(footer)

        let topLine = HairlineView()
        footer.addSubview(topLine)
        topLine.translatesAutoresizingMaskIntoConstraints = false

        clearButton.target = self
        clearButton.action = #selector(clearAll)
        clearDoneButton.target = self
        clearDoneButton.action = #selector(clearFinished)
        cancelButton.target = self
        cancelButton.action = #selector(cancelQueue)
        startButton.target = self
        startButton.action = #selector(startQueue)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.widthAnchor.constraint(equalToConstant: 140).isActive = true

        for button in [clearButton, clearDoneButton, cancelButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
        }
        footer.addSubview(clearButton)
        footer.addSubview(clearDoneButton)
        footer.addSubview(summaryLabel)
        footer.addSubview(cancelButton)
        footer.addSubview(startButton)
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 64),

            contentArea.bottomAnchor.constraint(equalTo: footer.topAnchor),

            topLine.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            topLine.topAnchor.constraint(equalTo: footer.topAnchor),
            topLine.heightAnchor.constraint(equalToConstant: 1),

            clearButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 18),
            clearButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            clearDoneButton.leadingAnchor.constraint(equalTo: clearButton.trailingAnchor, constant: 8),
            clearDoneButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            startButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -18),
            startButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            cancelButton.trailingAnchor.constraint(equalTo: startButton.leadingAnchor, constant: -10),
            cancelButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            summaryLabel.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -12),
            summaryLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            summaryLabel.leadingAnchor.constraint(greaterThanOrEqualTo: clearDoneButton.trailingAnchor, constant: 12),
        ])
    }

    // MARK: - 数据刷新

    private func reloadAll() {
        settingsPanel.attach(model: model)
        ffmpegBadge.set(text: model.ffmpegVersion, tone: .neutral)
        syncRows()
        updateFooter()
        dropZone.setCompact(!model.jobs.isEmpty, fileCount: model.jobs.count)
    }

    private func syncRows() {
        let ids = model.jobs.map(\.id)
        let existing = Set(ids)

        for (id, row) in rows where !existing.contains(id) {
            row.removeFromSuperview()
            rows[id] = nil
        }

        for job in model.jobs {
            if let row = rows[job.id] {
                row.configure(job)
            } else {
                let row = JobRowView()
                row.attach(model: model)
                row.configure(job)
                let id = job.id
                row.onReveal = { [weak self] in self?.model.reveal(id) }
                row.onRetry = { [weak self] in self?.model.retry(id) }
                row.onRemove = { [weak self] in self?.model.remove(id) }
                rows[id] = row
                listStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            }
        }

        // 保证顺序与 model.jobs 一致
        let current = listStack.arrangedSubviews.compactMap { ($0 as? JobRowView)?.jobID }
        if current != ids {
            for view in listStack.arrangedSubviews {
                view.removeFromSuperview()
            }
            for job in model.jobs {
                if let row = rows[job.id] {
                    listStack.addArrangedSubview(row)
                }
            }
        }
    }

    private func updateFooter() {
        summaryLabel.stringValue = model.summaryText
        clearButton.isEnabled = !model.jobs.isEmpty && !model.isRunning
        clearDoneButton.isEnabled = model.doneCount > 0 && !model.isRunning
        cancelButton.isHidden = !model.isRunning
        startButton.isEnabled = model.canStart
        startButton.title = model.isRunning ? L10n.t("btn.transcoding") : L10n.t("btn.start")
        folderButton.isEnabled = !model.jobs.isEmpty
    }

    // MARK: - AppModelObserver

    func modelJobsDidChange(_ model: AppModel) {
        syncRows()
        updateFooter()
        dropZone.setCompact(!model.jobs.isEmpty, fileCount: model.jobs.count)
        settingsPanel.syncFromModel()
    }

    func modelJobDidUpdate(_ model: AppModel, id: UUID) {
        guard let job = model.job(for: id) else { return }
        rows[id]?.updateStatus(job)
        updateFooter()
    }

    func modelSettingsDidChange(_ model: AppModel) {
        settingsPanel.syncFromModel()
    }

    func modelQueueDidFinish(_ model: AppModel) {
        NSSound(named: "Glass")?.play()
    }

    func modelDidProduceMessage(_ model: AppModel, message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.t("msg.title")
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.t("btn.ok"))
        if let window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    // MARK: - 拖放

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if urls(from: sender).isEmpty { return [] }
        dropZone.setDragActive(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropZone.setDragActive(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        dropZone.setDragActive(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropZone.setDragActive(false)
        let urls = urls(from: sender)
        guard !urls.isEmpty else { return false }
        model.addFiles(urls)
        return true
    }

    private func urls(from info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }

    // MARK: - 动作

    @objc private func startQueue() { model.start() }
    @objc private func cancelQueue() { model.cancel() }
    @objc private func clearAll() { model.clearAll() }
    @objc private func clearFinished() { model.clearFinished() }
    @objc private func openOutputFolder() { model.openOutputFolder() }
}
