import AppKit

/// 拖放区域：空列表时是大卡片，有文件时收成一条。
final class DropZoneView: NSView {
    var onPickFiles: (() -> Void)?
    var onPickFolder: (() -> Void)?

    private let gradientLayer = CAGradientLayer()
    private let borderLayer = CAShapeLayer()
    private let emptyStack = NSStackView()
    private let compactStack = NSStackView()
    private let countLabel = Label.make("", size: 11, color: .secondaryLabelColor)
    private let iconView = NSImageView()
    private var heightConstraint: NSLayoutConstraint?
    private(set) var isCompact = false
    private(set) var isDragActive = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        gradientLayer.startPoint = CGPoint(x: 0, y: 1)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0)
        gradientLayer.cornerRadius = 14
        layer?.addSublayer(gradientLayer)

        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.lineWidth = 1.5
        borderLayer.lineDashPattern = [7, 5]
        borderLayer.cornerRadius = 14
        layer?.addSublayer(borderLayer)

        buildEmptyStack()
        buildCompactStack()

        heightConstraint = heightAnchor.constraint(equalToConstant: 214)
        heightConstraint?.isActive = true

        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func buildEmptyStack() {
        let iconHost = NSView()
        iconHost.translatesAutoresizingMaskIntoConstraints = false
        iconHost.addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = Symbols.tinted(Symbols.image("square.and.arrow.down.on.square", size: 30, weight: .light), Theme.accent)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: iconHost.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconHost.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34),
            iconHost.heightAnchor.constraint(equalToConstant: 38),
        ])

        let title = Label.make(L10n.t("drop.title"), size: 14, weight: .medium)
        title.alignment = .center
        let subtitle = Label.make(L10n.t("drop.subtitle"), size: 11, color: .secondaryLabelColor)
        subtitle.alignment = .center
        subtitle.lineBreakMode = .byTruncatingTail

        let pick = GradientButton(title: L10n.t("btn.chooseFiles"), symbol: "plus", large: false)
        pick.target = self
        pick.action = #selector(handlePickFiles)

        let folder = PillButton(title: L10n.t("btn.chooseFolder"))
        folder.target = self
        folder.action = #selector(handlePickFolder)

        let buttons = NSStackView(views: [pick, folder])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.alignment = .centerY

        emptyStack.orientation = .vertical
        emptyStack.alignment = .centerX
        emptyStack.spacing = 8
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        emptyStack.addArrangedSubview(iconHost)
        emptyStack.addArrangedSubview(title)
        emptyStack.addArrangedSubview(subtitle)
        emptyStack.setCustomSpacing(14, after: subtitle)
        emptyStack.addArrangedSubview(buttons)
        addSubview(emptyStack)

        NSLayoutConstraint.activate([
            emptyStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
        ])
    }

    private func buildCompactStack() {
        let plus = NSImageView()
        plus.image = Symbols.tinted(Symbols.image("plus.circle.fill", size: 14, weight: .semibold), Theme.accent)
        plus.translatesAutoresizingMaskIntoConstraints = false
        plus.widthAnchor.constraint(equalToConstant: 16).isActive = true
        plus.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let hint = Label.make(L10n.t("drop.continue"), size: 12, color: .secondaryLabelColor)
        let pick = LinkButton(title: L10n.t("btn.chooseFiles"))
        pick.target = self
        pick.action = #selector(handlePickFiles)
        let folder = LinkButton(title: L10n.t("btn.chooseFolder"))
        folder.target = self
        folder.action = #selector(handlePickFolder)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        compactStack.orientation = .horizontal
        compactStack.alignment = .centerY
        compactStack.spacing = 8
        compactStack.translatesAutoresizingMaskIntoConstraints = false
        compactStack.addArrangedSubview(plus)
        compactStack.addArrangedSubview(hint)
        compactStack.addArrangedSubview(pick)
        compactStack.addArrangedSubview(folder)
        compactStack.addArrangedSubview(spacer)
        compactStack.addArrangedSubview(countLabel)
        addSubview(compactStack)

        NSLayoutConstraint.activate([
            compactStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            compactStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            compactStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        compactStack.isHidden = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        borderLayer.frame = bounds
        borderLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            cornerWidth: 13, cornerHeight: 13, transform: nil
        )
        CATransaction.commit()
    }

    func setCompact(_ compact: Bool, fileCount: Int) {
        let countText = L10n.t("drop.files", fileCount)
        guard compact != isCompact || countLabel.stringValue != countText else { return }
        isCompact = compact
        emptyStack.isHidden = compact
        compactStack.isHidden = !compact
        countLabel.stringValue = L10n.t("drop.files", fileCount)
        heightConstraint?.constant = compact ? 52 : 214
        needsDisplay = true
    }

    func setDragActive(_ active: Bool) {
        guard active != isDragActive else { return }
        isDragActive = active
        updateAppearance()
    }

    private func updateAppearance() {
        let top = Theme.accent.withAlphaComponent(isDragActive ? 0.26 : 0.11)
        let bottom = Theme.accentDeep.withAlphaComponent(isDragActive ? 0.20 : 0.055)
        gradientLayer.colors = [top.cgColor, bottom.cgColor]
        borderLayer.strokeColor = (isDragActive ? Theme.accent : Theme.accent.withAlphaComponent(0.38)).cgColor
        iconView.image = Symbols.tinted(
            Symbols.image(isDragActive ? "arrow.down.circle.fill" : "square.and.arrow.down.on.square", size: 30, weight: .light),
            Theme.accent
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        if !isCompact { onPickFiles?() }
    }

    @objc private func handlePickFiles() { onPickFiles?() }
    @objc private func handlePickFolder() { onPickFolder?() }
}
