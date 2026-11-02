import AppKit

/// 队列中的一行（内部手动布局，避免栈视图的尺寸歧义）
final class JobRowView: CardView {
    var onReveal: (() -> Void)?
    var onRetry: (() -> Void)?
    var onRemove: (() -> Void)?

    private(set) var jobID: UUID?
    private weak var model: AppModel?

    private let iconTile = IconTile(symbol: "film", colors: [Theme.accent, Theme.accentDeep])
    private let titleLabel = Label.make("", size: 12.5, weight: .medium)
    private let extBadge = BadgeView(text: "", tone: .neutral)
    private let metaLabel = Label.make("", size: 10.5, color: .secondaryLabelColor, mono: true)
    private let messageLabel = Label.make("", size: 10.5, color: Theme.bad)
    private let progressBar = ProgressBarView()
    private let percentLabel = Label.make("0%", size: 10, weight: .semibold, color: Theme.accent, mono: true)
    private let speedLabel = Label.make("", size: 10, color: .secondaryLabelColor, mono: true)
    private let statusBadge = BadgeView(text: L10n.t("status.waiting"), tone: .neutral)
    private let revealButton = NSButton()

    private var hovering = false
    private var tracking: NSTrackingArea?

    private let iconSize: CGFloat = 34
    private let horizontalPadding: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cornerRadius = 11
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 62)
    }

    private func setup() {
        for view in [iconTile, titleLabel, extBadge, metaLabel, messageLabel,
                     progressBar, percentLabel, speedLabel, statusBadge] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = true
            addSubview(view)
        }

        titleLabel.lineBreakMode = .byTruncatingMiddle
        metaLabel.lineBreakMode = .byTruncatingTail
        messageLabel.lineBreakMode = .byTruncatingTail

        revealButton.image = Symbols.image("arrow.up.forward.app", size: 12, weight: .medium)
        revealButton.isBordered = false
        revealButton.bezelStyle = .regularSquare
        revealButton.target = self
        revealButton.action = #selector(handleReveal)
        revealButton.toolTip = L10n.t("row.reveal")
        revealButton.translatesAutoresizingMaskIntoConstraints = true
        revealButton.isHidden = true
        addSubview(revealButton)

        progressBar.isHidden = true
        percentLabel.isHidden = true
        speedLabel.isHidden = true
        messageLabel.isHidden = true

        menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let reveal = NSMenuItem(title: L10n.t("row.reveal"), action: #selector(handleReveal), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
        let retry = NSMenuItem(title: L10n.t("row.retry"), action: #selector(handleRetry), keyEquivalent: "")
        retry.target = self
        menu.addItem(retry)
        menu.addItem(NSMenuItem.separator())
        let remove = NSMenuItem(title: L10n.t("row.remove"), action: #selector(handleRemove), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        return menu
    }

    // MARK: - 布局

    override func layout() {
        super.layout()

        let width = bounds.width
        let height = bounds.height

        iconTile.frame = NSRect(x: horizontalPadding,
                                y: (height - iconSize) / 2,
                                width: iconSize, height: iconSize)

        // 右侧状态区
        let badgeSize = statusBadge.intrinsicContentSize
        let revealWidth: CGFloat = revealButton.isHidden ? 0 : 20
        let revealGap: CGFloat = revealButton.isHidden ? 0 : 6
        let statusWidth = badgeSize.width + revealGap + revealWidth
        let statusX = width - horizontalPadding - statusWidth

        statusBadge.frame = NSRect(x: statusX,
                                   y: (height - badgeSize.height) / 2,
                                   width: badgeSize.width, height: badgeSize.height)
        revealButton.frame = NSRect(x: statusBadge.frame.maxX + revealGap,
                                    y: (height - 16) / 2,
                                    width: revealWidth, height: 16)

        // 文本区
        let textX = iconTile.frame.maxX + 11
        let textWidth = max(60, statusX - 10 - textX)
        let titleY: CGFloat = 11
        let secondY: CGFloat = 31

        let badgeWidth = extBadge.intrinsicContentSize.width
        if !extBadge.isHidden, badgeWidth > 0 {
            let titleFont = titleLabel.font ?? Theme.font(12.5, .medium)
            let naturalWidth = (titleLabel.stringValue as NSString).size(withAttributes: [.font: titleFont]).width + 10
            let titleWidth = min(naturalWidth, max(40, textWidth - badgeWidth - 6))
            titleLabel.frame = NSRect(x: textX, y: titleY, width: titleWidth, height: 17)
            extBadge.frame = NSRect(x: textX + titleWidth + 6, y: titleY - 1,
                                    width: badgeWidth, height: 18)
        } else {
            titleLabel.frame = NSRect(x: textX, y: titleY, width: textWidth, height: 17)
        }
        titleLabel.cell?.truncatesLastVisibleLine = true

        metaLabel.frame = NSRect(x: textX, y: secondY, width: textWidth, height: 15)
        messageLabel.frame = NSRect(x: textX, y: secondY, width: textWidth, height: 15)

        // 进度行
        let percentWidth: CGFloat = 38
        let speedWidth: CGFloat = 46
        let gap: CGFloat = 8
        let barWidth = max(50, textWidth - percentWidth - speedWidth - gap * 2 - 4)
        progressBar.frame = NSRect(x: textX, y: secondY + 5, width: barWidth, height: 4)
        percentLabel.frame = NSRect(x: textX + barWidth + gap, y: secondY, width: percentWidth, height: 14)
        speedLabel.frame = NSRect(x: textX + barWidth + gap + percentWidth + gap,
                                  y: secondY, width: speedWidth, height: 14)
    }

    // MARK: - 更新

    func attach(model: AppModel) {
        self.model = model
    }

    func configure(_ job: Job) {
        jobID = job.id
        titleLabel.stringValue = job.displayName
        titleLabel.toolTip = job.url.path
        extBadge.set(text: job.fileExtension, tone: .neutral)
        extBadge.isHidden = job.fileExtension.isEmpty

        let isImage = job.info?.isImage ?? false
        let isVideo = (job.info?.hasVideo ?? true) && !isImage
        iconTile.symbolName = isImage ? "photo" : (isVideo ? "film" : "waveform")
        iconTile.gradientColors = isImage
            ? [Theme.amber, Theme.pink]
            : (isVideo ? [Theme.accent, Theme.accentDeep] : [Theme.mint, Theme.teal])

        metaLabel.stringValue = metaText(job)
        updateStatus(job)
        needsLayout = true
    }

    func updateStatus(_ job: Job) {
        guard job.id == jobID else { return }

        switch job.status {
        case .waiting:
            statusBadge.set(text: L10n.t("status.waiting"), tone: .neutral)
            revealButton.isHidden = true
            show(progress: false, message: nil)
        case .probing:
            statusBadge.set(text: L10n.t("status.probing"), tone: .accent)
            revealButton.isHidden = true
            metaLabel.stringValue = L10n.t("status.analyzing")
            show(progress: false, message: nil)
        case .running:
            statusBadge.set(text: L10n.t("status.running"), tone: .accent)
            revealButton.isHidden = true
            show(progress: true, message: nil)
            progressBar.progress = job.progress
            percentLabel.stringValue = "\(Int((job.progress * 100).rounded()))%"
            speedLabel.stringValue = job.speed
        case .done:
            statusBadge.set(text: L10n.t("status.done"), tone: .success)
            revealButton.isHidden = false
            metaLabel.stringValue = metaText(job)
            show(progress: false, message: job.message.isEmpty ? nil : job.message)
        case .failed:
            statusBadge.set(text: L10n.t("status.failed"), tone: .danger)
            revealButton.isHidden = true
            show(progress: false, message: job.message.isEmpty ? L10n.t("status.failed") : job.message)
        case .cancelled:
            statusBadge.set(text: L10n.t("status.cancelled"), tone: .warning)
            revealButton.isHidden = true
            show(progress: false, message: nil)
        }
        needsLayout = true
    }

    private func show(progress: Bool, message: String?) {
        progressBar.isHidden = !progress
        percentLabel.isHidden = !progress
        speedLabel.isHidden = !progress
        metaLabel.isHidden = progress || message != nil
        messageLabel.isHidden = message == nil
        if let message {
            messageLabel.stringValue = message
            messageLabel.textColor = jobStatusColor
            messageLabel.toolTip = message
        }
    }

    private var jobStatusColor: NSColor {
        guard let id = jobID, let job = model?.job(for: id) else { return Theme.bad }
        return job.status == .done ? Theme.warn : Theme.bad
    }

    private func metaText(_ job: Job) -> String {
        var parts: [String] = [job.fileSize]
        if let info = job.info {
            if info.isImage {
                parts.append(L10n.t("status.image"))
                if info.width > 0 { parts.append(info.resolutionText) }
            } else {
                parts.append(Job.timecode(info.duration))
                if info.hasVideo, info.width > 0 {
                    parts.append(info.resolutionText)
                } else if info.hasVideo == false, info.hasAudio {
                    parts.append(L10n.t("status.audio"))
                }
            }
        }
        if job.status == .done, let out = job.outputURL {
            parts.append("→ " + out.lastPathComponent)
        }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: - 交互

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        fill = Theme.isDark ? NSColor(white: 1, alpha: 0.095) : NSColor(white: 1, alpha: 0.95)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        fill = Theme.cardFill
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onReveal?() }
    }

    @objc private func handleReveal() { onReveal?() }
    @objc private func handleRetry() { onRetry?() }
    @objc private func handleRemove() { onRemove?() }
}
