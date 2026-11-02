import AppKit

/// 小胶囊芯片（常用格式快捷选择）
final class ChipButton: NSButton {
    private var selected = false
    private var hovering = false
    private var tracking: NSTrackingArea?
    private var titleText: String

    var isSelected: Bool {
        get { selected }
        set { selected = newValue; needsDisplay = true }
    }

    init(title: String) {
        titleText = title
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryPushIn)
        font = Theme.font(10.5, .medium)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let w = (titleText as NSString).size(withAttributes: [.font: font ?? Theme.font(10.5)]).width
        return NSSize(width: w + 18, height: 22)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if selected {
            Theme.gradient(Theme.accent, Theme.accentDeep).draw(in: bounds, angle: -60)
        } else {
            Theme.subtleFill.setFill()
            path.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        if !selected {
            Theme.cardStroke.setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let color = selected ? NSColor.white : NSColor.labelColor
        let attrs: [NSAttributedString.Key: Any] = [.font: font ?? Theme.font(10.5), .foregroundColor: color]
        let size = (titleText as NSString).size(withAttributes: attrs)
        (titleText as NSString).draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attrs
        )
    }
}

/// 右侧设置面板
final class SettingsPanel: NSView, NSTextFieldDelegate {
    private weak var model: AppModel?
    private let stack = NSStackView()

    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let presetSaveButton = LinkButton(title: L10n.t("preset.save"))
    private let presetDeleteButton = LinkButton(title: L10n.t("preset.delete"))
    private var presetIDs: [String] = []
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private lazy var qualityControl = NSSegmentedControl(labels: Quality.allCases.map { $0.title },
                                                    trackingMode: .selectOne,
                                                    target: nil, action: nil)
    private let qualityHint = Label.make("", size: 10, color: .secondaryLabelColor)
    private let qualityTitle = Label.make("", size: 10, weight: .semibold, color: .secondaryLabelColor)
    private let resolutionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let resolutionTitle = Label.make("", size: 10, weight: .semibold, color: .secondaryLabelColor)
    private let bitratePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let bitrateTitle = Label.make("", size: 10, weight: .semibold, color: .secondaryLabelColor)
    private let hardwareSwitch = NSButton(checkboxWithTitle: L10n.t("settings.hardware"), target: nil, action: nil)
    private let hardwareHint = Label.make("", size: 10, color: .secondaryLabelColor)
    private let radioAlongside = NSButton(radioButtonWithTitle: L10n.t("settings.alongside"), target: nil, action: nil)
    private let radioCustom = NSButton(radioButtonWithTitle: L10n.t("settings.custom"), target: nil, action: nil)
    private let chooseDirButton = PillButton(title: L10n.t("btn.choose"))
    private let pathLabel = Label.make("", size: 10, color: .secondaryLabelColor)
    private let chipsRow = NSStackView()
    private let incompatibleHint = Label.make(L10n.t("settings.incompatible"), size: 10, color: .secondaryLabelColor)
    private let compressToggle = NSButton(checkboxWithTitle: L10n.t("settings.targetSize"), target: nil, action: nil)
    private let compressField = NSTextField()
    private let downscaleToggle = NSButton(checkboxWithTitle: L10n.t("settings.allowDownscale"), target: nil, action: nil)
    private let compressHint = Label.make(L10n.t("settings.targetSizeHint"), size: 10, color: .secondaryLabelColor)
    private var compressViews: [NSView] = []
    private let divider = HairlineView()
    private let infoBox = CardView()
    private let customRow = NSStackView()
    private let customHint = Label.make(L10n.t("settings.customHint"), size: 10, color: .secondaryLabelColor)
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private var chips: [String: ChipButton] = [:]
    private var videoViews: [NSView] = []
    private var bitrateViews: [NSView] = []
    private var hardwareViews: [NSView] = []

    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    func attach(model: AppModel) {
        self.model = model
        reloadPresets()
        syncFromModel()
    }

    // MARK: - 构建

    private func setup() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // 预设
        section(L10n.t("preset.title"))
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)
        presetPopup.font = Theme.font(12)
        presetPopup.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(presetPopup)
        presetSaveButton.target = self
        presetSaveButton.action = #selector(savePreset)
        presetDeleteButton.target = self
        presetDeleteButton.action = #selector(deletePreset)
        let presetButtons = NSStackView(views: [presetSaveButton, presetDeleteButton])
        presetButtons.orientation = .horizontal
        presetButtons.spacing = 10
        presetButtons.alignment = .centerY
        stack.addArrangedSubview(presetButtons)
        stack.setCustomSpacing(16, after: presetButtons)

        // 输出格式
        section(L10n.t("settings.format"))
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        formatPopup.font = Theme.font(12)
        formatPopup.translatesAutoresizingMaskIntoConstraints = false
        buildFormatMenu()
        stack.addArrangedSubview(formatPopup)

        buildChips()
        stack.addArrangedSubview(chipsRow)
        incompatibleHint.lineBreakMode = .byWordWrapping
        incompatibleHint.maximumNumberOfLines = 0
        incompatibleHint.isHidden = true
        stack.addArrangedSubview(incompatibleHint)
        stack.setCustomSpacing(18, after: incompatibleHint)

        // 画质
        qualityTitle.stringValue = L10n.t("settings.quality")
        videoViews.append(qualityTitle)
        stack.addArrangedSubview(qualityTitle)
        qualityControl.target = self
        qualityControl.action = #selector(qualityChanged)
        qualityControl.selectedSegment = 1
        qualityControl.font = Theme.font(11)
        qualityControl.translatesAutoresizingMaskIntoConstraints = false
        videoViews.append(qualityControl)
        stack.addArrangedSubview(qualityControl)
        videoViews.append(qualityHint)
        stack.addArrangedSubview(qualityHint)
        stack.setCustomSpacing(18, after: qualityHint)

        // 分辨率
        resolutionTitle.stringValue = L10n.t("settings.resolution")
        videoViews.append(resolutionTitle)
        stack.addArrangedSubview(resolutionTitle)
        resolutionPopup.target = self
        resolutionPopup.action = #selector(resolutionChanged)
        resolutionPopup.font = Theme.font(12)
        resolutionPopup.translatesAutoresizingMaskIntoConstraints = false
        for (index, preset) in ResolutionPreset.allCases.enumerated() {
            resolutionPopup.addItem(withTitle: preset.title)
            resolutionPopup.lastItem?.tag = index
        }
        videoViews.append(resolutionPopup)
        stack.addArrangedSubview(resolutionPopup)

        // 自定义分辨率
        configureSizeField(widthField, placeholder: L10n.t("settings.width"))
        configureSizeField(heightField, placeholder: L10n.t("settings.height"))
        let times = Label.make("×", size: 12, color: .secondaryLabelColor)
        let customSpacer = NSView()
        customSpacer.translatesAutoresizingMaskIntoConstraints = false
        customSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        customRow.orientation = .horizontal
        customRow.spacing = 6
        customRow.alignment = .centerY
        customRow.translatesAutoresizingMaskIntoConstraints = false
        customRow.addArrangedSubview(widthField)
        customRow.addArrangedSubview(times)
        customRow.addArrangedSubview(heightField)
        customRow.addArrangedSubview(customSpacer)
        videoViews.append(customRow)
        stack.addArrangedSubview(customRow)
        customHint.lineBreakMode = .byWordWrapping
        customHint.maximumNumberOfLines = 0
        videoViews.append(customHint)
        stack.addArrangedSubview(customHint)
        stack.setCustomSpacing(18, after: customHint)

        // 音频码率
        bitrateTitle.stringValue = L10n.t("settings.bitrate")
        bitrateViews.append(bitrateTitle)
        stack.addArrangedSubview(bitrateTitle)
        bitratePopup.target = self
        bitratePopup.action = #selector(bitrateChanged)
        bitratePopup.font = Theme.font(12)
        bitratePopup.translatesAutoresizingMaskIntoConstraints = false
        for (index, bitrate) in AudioBitrate.allCases.enumerated() {
            bitratePopup.addItem(withTitle: bitrate.title)
            bitratePopup.lastItem?.tag = index
        }
        bitrateViews.append(bitratePopup)
        stack.addArrangedSubview(bitratePopup)
        stack.setCustomSpacing(18, after: bitratePopup)

        // 压缩
        let compressTitle = Label.make(L10n.t("settings.compression"), size: 10, weight: .semibold, color: .secondaryLabelColor)
        compressViews.append(compressTitle)
        stack.addArrangedSubview(compressTitle)

        compressToggle.target = self
        compressToggle.action = #selector(compressToggled)
        compressToggle.font = Theme.font(12)
        compressToggle.translatesAutoresizingMaskIntoConstraints = false
        compressField.placeholderString = "2.0"
        compressField.font = Theme.font(12)
        compressField.alignment = .right
        compressField.bezelStyle = .roundedBezel
        compressField.translatesAutoresizingMaskIntoConstraints = false
        compressField.target = self
        compressField.action = #selector(compressValueChanged)
        compressField.delegate = self
        compressField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        let unit = Label.make(L10n.t("settings.targetSizeUnit"), size: 11, color: .secondaryLabelColor)
        let compressRow = NSStackView(views: [compressToggle, compressField, unit])
        compressRow.orientation = .horizontal
        compressRow.spacing = 6
        compressRow.alignment = .centerY
        compressViews.append(compressRow)
        stack.addArrangedSubview(compressRow)

        downscaleToggle.target = self
        downscaleToggle.action = #selector(downscaleToggled)
        downscaleToggle.font = Theme.font(12)
        downscaleToggle.translatesAutoresizingMaskIntoConstraints = false
        compressViews.append(downscaleToggle)
        stack.addArrangedSubview(downscaleToggle)

        compressHint.lineBreakMode = .byWordWrapping
        compressHint.maximumNumberOfLines = 0
        compressViews.append(compressHint)
        stack.addArrangedSubview(compressHint)
        stack.setCustomSpacing(18, after: compressHint)

        // 硬件加速
        hardwareSwitch.target = self
        hardwareSwitch.action = #selector(hardwareChanged)
        hardwareSwitch.font = Theme.font(12)
        hardwareSwitch.translatesAutoresizingMaskIntoConstraints = false
        hardwareViews = [hardwareSwitch, hardwareHint]
        stack.addArrangedSubview(hardwareSwitch)
        stack.addArrangedSubview(hardwareHint)
        stack.setCustomSpacing(18, after: hardwareHint)

        divider.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(divider)
        stack.setCustomSpacing(18, after: divider)

        // 输出位置
        section(L10n.t("settings.output"))
        radioAlongside.target = self
        radioAlongside.action = #selector(outputModeChanged(_:))
        radioCustom.target = self
        radioCustom.action = #selector(outputModeChanged(_:))
        radioAlongside.font = Theme.font(12)
        radioCustom.font = Theme.font(12)
        radioAlongside.translatesAutoresizingMaskIntoConstraints = false
        radioCustom.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(radioAlongside)
        stack.addArrangedSubview(radioCustom)

        chooseDirButton.target = self
        chooseDirButton.action = #selector(chooseDirectory)
        stack.addArrangedSubview(chooseDirButton)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        stack.addArrangedSubview(pathLabel)
        stack.setCustomSpacing(18, after: pathLabel)

        // 说明
        infoBox.cornerRadius = 8
        infoBox.fill = Theme.accent.withAlphaComponent(0.07)
        infoBox.stroke = Theme.accent.withAlphaComponent(0.12)
        infoBox.translatesAutoresizingMaskIntoConstraints = false
        let infoLabel = Label.make(L10n.t("settings.info"),
                                   size: 10.5, color: .secondaryLabelColor)
        infoLabel.lineBreakMode = .byWordWrapping
        infoLabel.maximumNumberOfLines = 0
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoBox.addSubview(infoLabel)
        NSLayoutConstraint.activate([
            infoLabel.leadingAnchor.constraint(equalTo: infoBox.leadingAnchor, constant: 9),
            infoLabel.trailingAnchor.constraint(equalTo: infoBox.trailingAnchor, constant: -9),
            infoLabel.topAnchor.constraint(equalTo: infoBox.topAnchor, constant: 8),
            infoLabel.bottomAnchor.constraint(equalTo: infoBox.bottomAnchor, constant: -8),
        ])
        stack.addArrangedSubview(infoBox)

        // 所有视图已进入层级后再建立宽度约束
        for view in [presetPopup, formatPopup, qualityControl, resolutionPopup, bitratePopup, divider, infoBox] as [NSView] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        reloadPresets()
        for view in [qualityHint, hardwareHint, pathLabel] as [NSView] {
            view.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
        }
    }

    private func configureSizeField(_ field: NSTextField, placeholder: String) {
        field.placeholderString = placeholder
        field.font = Theme.font(12)
        field.alignment = .center
        field.bezelStyle = .roundedBezel
        field.translatesAutoresizingMaskIntoConstraints = false
        field.delegate = self
        field.target = self
        field.action = #selector(customResolutionEdited)
        field.widthAnchor.constraint(equalToConstant: 66).isActive = true
    }

    private func section(_ text: String) {
        let label = Label.make(text, size: 10, weight: .semibold, color: .secondaryLabelColor)
        stack.addArrangedSubview(label)
    }

    private func buildChips() {
        chipsRow.orientation = .horizontal
        chipsRow.spacing = 6
        chipsRow.alignment = .centerY
        chipsRow.translatesAutoresizingMaskIntoConstraints = false
        for id in ["mp4", "mp3", "png", "gif"] {
            let chip = ChipButton(title: id.uppercased())
            chip.target = self
            chip.action = #selector(chipTapped(_:))
            chips[id] = chip
            chipsRow.addArrangedSubview(chip)
        }
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        chipsRow.addArrangedSubview(spacer)
    }

    private func buildFormatMenu() {
        let menu = NSMenu()
        menu.font = Theme.font(12)

        func header(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.tag = -1
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: Theme.font(9.5, .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )
            menu.addItem(item)
        }

        func add(_ formats: [OutputFormat]) {
            for format in formats {
                let item = NSMenuItem(title: format.menuLabel, action: nil, keyEquivalent: "")
                item.tag = Catalog.all.firstIndex(where: { $0.id == format.id }) ?? -1
                menu.addItem(item)
            }
        }

        func separator() {
            let item = NSMenuItem.separator()
            item.tag = -1
            menu.addItem(item)
        }

        header(L10n.t("group.video"))
        add(Catalog.videoFormats)
        separator()
        header(L10n.t("group.audio"))
        add(Catalog.audioFormats)
        separator()
        header(L10n.t("group.image"))
        add(Catalog.imageFormats)
        formatPopup.menu = menu
    }

    // MARK: - 同步

    func syncFromModel() {
        guard let model else { return }
        let format = model.currentFormat
        let isVideo = format.kind == .video && !format.isAnimatedImage
        let running = model.isRunning

        if let catalogIndex = Catalog.all.firstIndex(where: { $0.id == format.id }) {
            _ = formatPopup.selectItem(withTag: catalogIndex)
        }
        let allowed = Set(model.availableFormats.map(\.id))
        for item in formatPopup.itemArray where item.tag >= 0 && item.tag < Catalog.all.count {
            item.isEnabled = allowed.contains(Catalog.all[item.tag].id) && !running
        }
        incompatibleHint.isHidden = allowed.count == Catalog.all.count
        for (id, chip) in chips {
            chip.isSelected = (id == format.id)
            chip.isEnabled = !running && allowed.contains(id)
        }

        let showSizeControls = isVideo || format.isImage
        for view in videoViews { view.isHidden = !showSizeControls }
        for view in bitrateViews { view.isHidden = format.lossless || format.isImage }
        for view in hardwareViews { view.isHidden = format.kind != .video }

        let mediaFormat = format.kind == .image || format.kind == .video
        for view in compressViews { view.isHidden = !mediaFormat }
        compressToggle.state = model.targetSizeMB != nil ? .on : .off
        if compressField.currentEditor() == nil {
            compressField.stringValue = model.targetSizeMB.map { String(format: "%.1f", $0) } ?? ""
        }
        compressField.isEnabled = model.targetSizeMB != nil && !running
        downscaleToggle.state = model.allowDownscale ? .on : .off
        downscaleToggle.isEnabled = model.targetSizeMB != nil && !running

        qualityControl.selectedSegment = Quality.allCases.firstIndex(of: model.quality) ?? 1
        qualityHint.stringValue = model.quality.detail
        _ = resolutionPopup.selectItem(withTag: ResolutionPreset.allCases.firstIndex(of: model.resolution) ?? 0)
        _ = bitratePopup.selectItem(withTag: AudioBitrate.allCases.firstIndex(of: model.audioBitrate) ?? 2)

        let showCustom = isVideo && model.resolution == .custom
        customRow.isHidden = !showCustom
        customHint.isHidden = !showCustom
        if widthField.currentEditor() == nil {
            widthField.stringValue = model.customWidth.map(String.init) ?? ""
        }
        if heightField.currentEditor() == nil {
            heightField.stringValue = model.customHeight.map(String.init) ?? ""
        }
        widthField.isEnabled = !running
        heightField.isEnabled = !running

        hardwareSwitch.state = model.hardware ? .on : .off
        hardwareSwitch.isEnabled = model.hardwareAvailable && isVideo && !running
        hardwareHint.stringValue = model.hardwareAvailable
            ? (isVideo ? L10n.t("settings.hwHint") : L10n.t("settings.hwVideoOnly"))
            : L10n.t("settings.hwUnsupported")

        radioAlongside.state = model.outputMode == .alongside ? .on : .off
        radioCustom.state = model.outputMode == .custom ? .on : .off
        chooseDirButton.isHidden = model.outputMode != .custom
        pathLabel.isHidden = model.outputMode != .custom
        pathLabel.stringValue = model.customDirectory?.path ?? L10n.t("settings.noFolder")
        pathLabel.toolTip = model.customDirectory?.path

        formatPopup.isEnabled = !running
        qualityControl.isEnabled = !running
        resolutionPopup.isEnabled = !running
        bitratePopup.isEnabled = !running && !format.lossless
        radioAlongside.isEnabled = !running
        radioCustom.isEnabled = !running
        chooseDirButton.isEnabled = !running
    }

    // MARK: - 文本输入

    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField, field === compressField {
            model?.setTargetSizeMB(Double(field.stringValue))
            return
        }
        guard let field = obj.object as? NSTextField, field === widthField || field === heightField else { return }
        // 只接受数字
        let filtered = field.stringValue.filter { $0.isNumber }
        if filtered != field.stringValue {
            field.stringValue = filtered
        }
        commitCustomResolution()
    }

    // MARK: - 事件

    private func reloadPresets() {
        presetPopup.removeAllItems()
        presetPopup.addItem(withTitle: L10n.t("preset.none"))
        presetPopup.lastItem?.tag = -1
        presetIDs = [""]
        for preset in PresetStore.shared.all {
            presetPopup.addItem(withTitle: preset.displayName)
            presetPopup.lastItem?.tag = presetIDs.count - 1
            presetIDs.append(preset.id)
        }
        presetPopup.selectItem(at: 0)
        updatePresetButtons()
    }

    private func markCustomPreset() {
        if presetPopup.numberOfItems > 0 {
            presetPopup.selectItem(at: 0)
            updatePresetButtons()
        }
    }

    private func updatePresetButtons() {
        let index = presetPopup.indexOfSelectedItem
        let preset = (index > 0 && index < presetIDs.count)
            ? PresetStore.shared.preset(id: presetIDs[index]) : nil
        presetDeleteButton.isHidden = !(preset?.isBuiltin == false)
    }

    @objc private func presetChanged() {
        let index = presetPopup.indexOfSelectedItem
        guard index > 0, index < presetIDs.count,
              let preset = PresetStore.shared.preset(id: presetIDs[index]) else {
            updatePresetButtons()
            return
        }
        model?.apply(preset: preset)
        presetPopup.selectItem(at: index)
        updatePresetButtons()
    }

    @objc private func savePreset() {
        guard let model else { return }
        let alert = NSAlert()
        alert.messageText = L10n.t("preset.save")
        alert.informativeText = L10n.t("preset.namePrompt")
        alert.addButton(withTitle: L10n.t("btn.ok"))
        alert.addButton(withTitle: L10n.t("btn.cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = L10n.t("preset.namePlaceholder")
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = PresetStore.shared.add(name: name.isEmpty ? L10n.t("preset.custom") : name,
                                            from: model.currentSettingsSnapshot)
        reloadPresets()
        if let index = presetIDs.firstIndex(of: preset.id) {
            presetPopup.selectItem(at: index)
        } else {
            markCustomPreset()
        }
        updatePresetButtons()
    }

    @objc private func deletePreset() {
        let index = presetPopup.indexOfSelectedItem
        guard index >= 0, index < presetIDs.count,
              PresetStore.shared.preset(id: presetIDs[index])?.isBuiltin == false else { return }
        PresetStore.shared.remove(id: presetIDs[index])
        reloadPresets()
    }

    @objc private func formatChanged() {
        markCustomPreset()
        guard let title = formatPopup.selectedItem?.title,
              let format = Catalog.all.first(where: { $0.menuLabel == title }) else { return }
        model?.setFormat(format.id)
    }

    @objc private func qualityChanged() {
        markCustomPreset()
        let index = qualityControl.selectedSegment
        guard index >= 0, index < Quality.allCases.count else { return }
        model?.setQuality(Quality.allCases[index])
    }

    @objc private func resolutionChanged() {
        markCustomPreset()
        guard let tag = resolutionPopup.selectedItem?.tag, tag >= 0, tag < ResolutionPreset.allCases.count else { return }
        model?.setResolution(ResolutionPreset.allCases[tag])
    }

    @objc private func bitrateChanged() {
        markCustomPreset()
        guard let tag = bitratePopup.selectedItem?.tag, tag >= 0, tag < AudioBitrate.allCases.count else { return }
        model?.setAudioBitrate(AudioBitrate.allCases[tag])
    }

    @objc private func hardwareChanged() {
        markCustomPreset()
        model?.setHardware(hardwareSwitch.state == .on)
    }

    @objc private func outputModeChanged(_ sender: NSButton) {
        model?.setOutputMode(sender == radioCustom ? .custom : .alongside)
        if sender == radioCustom, model?.customDirectory == nil {
            model?.pickOutputDirectory()
        }
    }

    @objc private func chooseDirectory() {
        model?.pickOutputDirectory()
    }

    @objc private func compressToggled() {
        if compressToggle.state == .on {
            let value = Double(compressField.stringValue) ?? 2.0
            compressField.stringValue = String(format: "%.1f", value)
            model?.setTargetSizeMB(value)
        } else {
            model?.setTargetSizeMB(nil)
        }
    }

    @objc private func compressValueChanged() {
        model?.setTargetSizeMB(Double(compressField.stringValue))
    }

    @objc private func downscaleToggled() {
        model?.setAllowDownscale(downscaleToggle.state == .on)
    }

    @objc private func customResolutionEdited() {
        commitCustomResolution()
    }

    private func commitCustomResolution() {
        markCustomPreset()
        let rawWidth = widthField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawHeight = heightField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let width = Int(rawWidth).flatMap { $0 > 0 ? $0 : nil }
        let height = Int(rawHeight).flatMap { $0 > 0 ? $0 : nil }
        model?.setCustomResolution(width: width, height: height)
    }

    @objc private func chipTapped(_ sender: ChipButton) {
        guard let id = chips.first(where: { $0.value === sender })?.key else { return }
        model?.setFormat(id)
    }
}
