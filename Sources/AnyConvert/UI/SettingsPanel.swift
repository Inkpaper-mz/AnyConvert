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

    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let qualityControl = NSSegmentedControl(labels: ["高质量", "标准", "小体积"],
                                                    trackingMode: .selectOne,
                                                    target: nil, action: nil)
    private let qualityHint = Label.make("", size: 10, color: .secondaryLabelColor)
    private let qualityTitle = Label.make("", size: 10, weight: .semibold, color: .secondaryLabelColor)
    private let resolutionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let resolutionTitle = Label.make("", size: 10, weight: .semibold, color: .secondaryLabelColor)
    private let bitratePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let bitrateTitle = Label.make("", size: 10, weight: .semibold, color: .secondaryLabelColor)
    private let hardwareSwitch = NSButton(checkboxWithTitle: "Apple 硬件加速", target: nil, action: nil)
    private let hardwareHint = Label.make("", size: 10, color: .secondaryLabelColor)
    private let radioAlongside = NSButton(radioButtonWithTitle: "与源文件相同文件夹", target: nil, action: nil)
    private let radioCustom = NSButton(radioButtonWithTitle: "指定文件夹", target: nil, action: nil)
    private let chooseDirButton = PillButton(title: "选择文件夹…")
    private let pathLabel = Label.make("", size: 10, color: .secondaryLabelColor)
    private let chipsRow = NSStackView()
    private let divider = HairlineView()
    private let infoBox = CardView()
    private let customRow = NSStackView()
    private let customHint = Label.make("留空则自动计算；同时填写会等比适配进该尺寸", size: 10, color: .secondaryLabelColor)
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private var chips: [String: ChipButton] = [:]
    private var videoViews: [NSView] = []
    private var bitrateViews: [NSView] = []

    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    func attach(model: AppModel) {
        self.model = model
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

        // 输出格式
        section("输出格式")
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        formatPopup.font = Theme.font(12)
        formatPopup.translatesAutoresizingMaskIntoConstraints = false
        buildFormatMenu()
        stack.addArrangedSubview(formatPopup)

        buildChips()
        stack.addArrangedSubview(chipsRow)
        stack.setCustomSpacing(18, after: chipsRow)

        // 画质
        qualityTitle.stringValue = "画质"
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
        resolutionTitle.stringValue = "分辨率"
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
        configureSizeField(widthField, placeholder: "宽")
        configureSizeField(heightField, placeholder: "高")
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
        bitrateTitle.stringValue = "音频码率"
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

        // 硬件加速
        hardwareSwitch.target = self
        hardwareSwitch.action = #selector(hardwareChanged)
        hardwareSwitch.font = Theme.font(12)
        hardwareSwitch.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(hardwareSwitch)
        stack.addArrangedSubview(hardwareHint)
        stack.setCustomSpacing(18, after: hardwareHint)

        divider.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(divider)
        stack.setCustomSpacing(18, after: divider)

        // 输出位置
        section("输出位置")
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
        let infoLabel = Label.make("支持 300+ 种输入格式。视频转音频会自动提取音轨，例如 MP4 → MP3。",
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
        for view in [formatPopup, qualityControl, resolutionPopup, bitratePopup, divider, infoBox] as [NSView] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
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
        for id in ["mp4", "mp3", "gif", "flac"] {
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
        for format in Catalog.videoFormats {
            let item = NSMenuItem(title: format.menuLabel, action: nil, keyEquivalent: "")
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        for format in Catalog.audioFormats {
            let item = NSMenuItem(title: format.menuLabel, action: nil, keyEquivalent: "")
            menu.addItem(item)
        }
        formatPopup.menu = menu
    }

    // MARK: - 同步

    func syncFromModel() {
        guard let model else { return }
        let format = model.currentFormat
        let isVideo = format.kind == .video && !format.isAnimatedImage
        let running = model.isRunning

        if let catalogIndex = Catalog.all.firstIndex(where: { $0.id == format.id }) {
            let menuIndex = catalogIndex < Catalog.videoFormats.count ? catalogIndex : catalogIndex + 1
            if menuIndex >= 0, menuIndex < formatPopup.numberOfItems {
                formatPopup.selectItem(at: menuIndex)
            }
        }
        for (id, chip) in chips {
            chip.isSelected = (id == format.id)
            chip.isEnabled = !running
        }

        for view in videoViews { view.isHidden = !isVideo }
        for view in bitrateViews { view.isHidden = format.lossless }

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
            ? (isVideo ? "VideoToolbox 编码 H.264，更快更省电" : "仅视频格式可用")
            : "当前环境不支持 VideoToolbox"

        radioAlongside.state = model.outputMode == .alongside ? .on : .off
        radioCustom.state = model.outputMode == .custom ? .on : .off
        chooseDirButton.isHidden = model.outputMode != .custom
        pathLabel.isHidden = model.outputMode != .custom
        pathLabel.stringValue = model.customDirectory?.path ?? "尚未选择文件夹"
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
        guard let field = obj.object as? NSTextField, field === widthField || field === heightField else { return }
        // 只接受数字
        let filtered = field.stringValue.filter { $0.isNumber }
        if filtered != field.stringValue {
            field.stringValue = filtered
        }
        commitCustomResolution()
    }

    // MARK: - 事件

    @objc private func formatChanged() {
        guard let title = formatPopup.selectedItem?.title,
              let format = Catalog.all.first(where: { $0.menuLabel == title }) else { return }
        model?.setFormat(format.id)
    }

    @objc private func qualityChanged() {
        let index = qualityControl.selectedSegment
        guard index >= 0, index < Quality.allCases.count else { return }
        model?.setQuality(Quality.allCases[index])
    }

    @objc private func resolutionChanged() {
        guard let tag = resolutionPopup.selectedItem?.tag, tag >= 0, tag < ResolutionPreset.allCases.count else { return }
        model?.setResolution(ResolutionPreset.allCases[tag])
    }

    @objc private func bitrateChanged() {
        guard let tag = bitratePopup.selectedItem?.tag, tag >= 0, tag < AudioBitrate.allCases.count else { return }
        model?.setAudioBitrate(AudioBitrate.allCases[tag])
    }

    @objc private func hardwareChanged() {
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

    @objc private func customResolutionEdited() {
        commitCustomResolution()
    }

    private func commitCustomResolution() {
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
