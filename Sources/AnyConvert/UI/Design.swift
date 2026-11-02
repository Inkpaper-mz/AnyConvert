import AppKit

// MARK: - 颜色与字体

enum Theme {
    static let accent = NSColor(srgbRed: 0.29, green: 0.47, blue: 0.98, alpha: 1)
    static let accentDeep = NSColor(srgbRed: 0.57, green: 0.38, blue: 0.96, alpha: 1)
    static let mint = NSColor(srgbRed: 0.16, green: 0.72, blue: 0.56, alpha: 1)
    static let teal = NSColor(srgbRed: 0.10, green: 0.62, blue: 0.72, alpha: 1) 
    static let ok = NSColor(srgbRed: 0.10, green: 0.66, blue: 0.42, alpha: 1)
    static let warn = NSColor(srgbRed: 0.93, green: 0.58, blue: 0.10, alpha: 1)
    static let bad = NSColor(srgbRed: 0.89, green: 0.26, blue: 0.28, alpha: 1)
    static let amber = NSColor(srgbRed: 0.98, green: 0.62, blue: 0.20, alpha: 1)
    static let pink = NSColor(srgbRed: 0.94, green: 0.36, blue: 0.58, alpha: 1)

    static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static var hairline: NSColor { NSColor.separatorColor.withAlphaComponent(0.55) }

    static var cardFill: NSColor {
        isDark ? NSColor(white: 1, alpha: 0.055) : NSColor(white: 1, alpha: 0.72)
    }

    static var cardStroke: NSColor {
        isDark ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.075)
    }

    static var subtleFill: NSColor {
        isDark ? NSColor(white: 1, alpha: 0.07) : NSColor(white: 0, alpha: 0.045)
    }

    static var sidebarFill: NSColor {
        isDark ? NSColor(white: 0, alpha: 0.16) : NSColor(white: 0, alpha: 0.022)
    }

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func gradient(_ start: NSColor, _ end: NSColor) -> NSGradient {
        NSGradient(starting: start, ending: end) ?? NSGradient(starting: start, ending: start)!
    }
}

// MARK: - 工具

enum Symbols {
    static func image(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    static func tinted(_ image: NSImage?, _ color: NSColor) -> NSImage? {
        guard let image else { return nil }
        let copy = NSImage(size: image.size)
        copy.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        copy.unlockFocus()
        copy.isTemplate = false
        return copy
    }
}

extension NSView {
    func pinToEdges(of parent: NSView, insets: NSEdgeInsets = NSEdgeInsetsZero) {
        translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: parent.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -insets.bottom),
        ])
    }
}

// MARK: - 卡片

/// 圆角卡片：填充 + 细描边
class CardView: NSView {
    var cornerRadius: CGFloat = 12 { didSet { needsDisplay = true } }
    var fill: NSColor = Theme.cardFill { didSet { needsDisplay = true } }
    var stroke: NSColor = Theme.cardStroke { didSet { needsDisplay = true } }
    var borderWidth: CGFloat = 1 { didSet { needsDisplay = true } }

    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.backgroundColor = fill.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = borderWidth
        layer?.borderColor = stroke.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// 1px 分隔线
final class HairlineView: NSView {
    var color: NSColor = Theme.hairline { didSet { needsDisplay = true } }

    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.backgroundColor = color.cgColor
    }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }
}

// MARK: - 图标块

/// 渐变圆角图标
final class IconTile: NSView {
    private let gradientLayer = CAGradientLayer()
    private let imageView = NSImageView()
    var gradientColors: [NSColor] = [Theme.accent, Theme.accentDeep] {
        didSet { needsDisplay = true }
    }
    var symbolName: String = "film" {
        didSet { reloadSymbol() }
    }
    var corner: CGFloat = 9 { didSet { needsDisplay = true } }

    init(symbol: String, colors: [NSColor], size: CGFloat = 34) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        symbolName = symbol
        gradientColors = colors
        layer?.cornerRadius = corner
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        gradientLayer.startPoint = CGPoint(x: 0, y: 1)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradientLayer)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentTintColor = .white
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: size * 0.5),
            imageView.heightAnchor.constraint(equalToConstant: size * 0.5),
        ])
        reloadSymbol()

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        CATransaction.commit()
    }

    override func updateLayer() {
        gradientLayer.colors = gradientColors.map(\.cgColor)
        layer?.cornerRadius = corner
        layer?.cornerCurve = .continuous
    }

    private func reloadSymbol() {
        imageView.image = Symbols.tinted(Symbols.image(symbolName, size: 16, weight: .semibold), .white)
        imageView.contentTintColor = nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - 徽章

final class BadgeView: NSView {
    enum Tone {
        case neutral, accent, success, warning, danger
    }

    private let label = NSTextField(labelWithString: "")
    private var tone: Tone = .neutral

    init(text: String = "", tone: Tone = .neutral) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.font(10, .medium)
        addSubview(label)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 18),
        ])
        set(text: text, tone: tone)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let font = label.font ?? Theme.font(10)
        let size = (label.stringValue as NSString).size(withAttributes: [.font: font])
        return NSSize(width: max(18, size.width + 14), height: 18)
    }

    func set(text: String, tone: Tone) {
        self.tone = tone
        label.stringValue = text
        invalidateIntrinsicContentSize()
        switch tone {
        case .neutral: label.textColor = .secondaryLabelColor
        case .accent: label.textColor = Theme.accent
        case .success: label.textColor = Theme.ok
        case .warning: label.textColor = Theme.warn
        case .danger: label.textColor = Theme.bad
        }
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let color: NSColor
        switch tone {
        case .neutral: color = Theme.subtleFill
        case .accent: color = Theme.accent.withAlphaComponent(0.13)
        case .success: color = Theme.ok.withAlphaComponent(0.14)
        case .warning: color = Theme.warn.withAlphaComponent(0.15)
        case .danger: color = Theme.bad.withAlphaComponent(0.14)
        }
        layer?.backgroundColor = color.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - 进度条

final class ProgressBarView: NSView {
    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }
    var trackColor: NSColor = Theme.subtleFill { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let track = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        (Theme.isDark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.07)).setFill()
        track.fill()

        let width = max(bounds.height, bounds.width * CGFloat(min(max(progress, 0), 1)))
        let fillRect = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        fill.addClip()
        Theme.gradient(Theme.accent, Theme.accentDeep).draw(in: fillRect, angle: 0)
        NSGraphicsContext.restoreGraphicsState()
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 60, height: 4) }
}

// MARK: - 按钮

/// 主按钮：渐变胶囊
final class GradientButton: NSButton {
    var symbolName: String? { didSet { needsDisplay = true } }
    private var hovering = false
    private var tracking: NSTrackingArea?
    private var titleText: String = ""

    override var title: String {
        get { titleText }
        set {
            titleText = newValue
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }

    init(title: String, symbol: String? = nil, large: Bool = false) {
        super.init(frame: .zero)
        self.titleText = title
        self.symbolName = symbol
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.setButtonType(.momentaryPushIn)
        self.font = Theme.font(large ? 13 : 12, .semibold)
        self.contentTintColor = .white
        self.translatesAutoresizingMaskIntoConstraints = false
        self.heightAnchor.constraint(equalToConstant: large ? 36 : 30).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        let textWidth = (titleText as NSString).size(withAttributes: [.font: font ?? Theme.font(12)]).width
        let iconWidth: CGFloat = symbolName != nil ? 17 : 0
        return NSSize(width: max(96, textWidth + iconWidth + 34), height: 36)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)

        NSGraphicsContext.saveGraphicsState()
        if !isEnabled {
            NSColor(white: 0.5, alpha: 0.35).setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
            drawContent(alpha: 0.75)
            return
        }

        path.addClip()
        let start = hovering ? Theme.accent.blended(withFraction: 0.08, of: .white) ?? Theme.accent : Theme.accent
        Theme.gradient(start, Theme.accentDeep).draw(in: bounds, angle: -70)
        NSGraphicsContext.restoreGraphicsState()

        drawContent(alpha: 1)
    }

    private func drawContent(alpha: CGFloat) {
        let white = NSColor.white.withAlphaComponent(alpha)
        let font = self.font ?? Theme.font(12, .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: white]
        let textSize = (titleText as NSString).size(withAttributes: attrs)

        let icon: NSImage? = symbolName.flatMap { Symbols.tinted(Symbols.image($0, size: 12, weight: .semibold), white) }
        let iconWidth: CGFloat = icon != nil ? 13 + 6 : 0
        let total = textSize.width + iconWidth
        var x = (bounds.width - total) / 2
        let baselineY = (bounds.height - textSize.height) / 2

        if let icon {
            icon.draw(in: NSRect(x: x, y: (bounds.height - 13) / 2, width: 13, height: 13))
            x += 19
        }
        (titleText as NSString).draw(at: NSPoint(x: x, y: baselineY), withAttributes: attrs)
    }
}

/// 次按钮：浅色圆角
final class PillButton: NSButton {
    private var hovering = false
    private var tracking: NSTrackingArea?
    private var titleText = ""
    var horizontalPadding: CGFloat = 12

    override var title: String {
        get { titleText }
        set {
            titleText = newValue
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }

    init(title: String) {
        super.init(frame: .zero)
        titleText = title
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryPushIn)
        font = Theme.font(12, .medium)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override var intrinsicContentSize: NSSize {
        let width = (titleText as NSString).size(withAttributes: [.font: font ?? Theme.font(12)]).width
        return NSSize(width: width + horizontalPadding * 2, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        let fill: NSColor
        if !isEnabled {
            fill = Theme.subtleFill
        } else if hovering {
            fill = Theme.isDark ? NSColor(white: 1, alpha: 0.13) : NSColor(white: 0, alpha: 0.085)
        } else {
            fill = Theme.subtleFill
        }
        fill.setFill()
        path.fill()

        Theme.cardStroke.setStroke()
        path.lineWidth = 1
        path.stroke()

        if !isEnabled {
            NSGraphicsContext.current?.cgContext.setAlpha(0.55)
        }
        let color = isEnabled ? NSColor.labelColor : NSColor.secondaryLabelColor
        let attrs: [NSAttributedString.Key: Any] = [.font: font ?? Theme.font(12), .foregroundColor: color]
        let size = (titleText as NSString).size(withAttributes: attrs)
        (titleText as NSString).draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attrs
        )
    }
}

/// 纯文字链接按钮
final class LinkButton: NSButton {
    private var titleText = ""

    override var title: String {
        get { titleText }
        set {
            titleText = newValue
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }

    init(title: String) {
        super.init(frame: .zero)
        titleText = title
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let width = (titleText as NSString).size(withAttributes: [.font: Theme.font(12, .medium)]).width
        return NSSize(width: width + 4, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Theme.font(12, .medium),
            .foregroundColor: isEnabled ? Theme.accent : NSColor.secondaryLabelColor.withAlphaComponent(0.6),
        ]
        let size = (titleText as NSString).size(withAttributes: attrs)
        (titleText as NSString).draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attrs
        )
    }
}

// MARK: - 文本标签工厂

enum Label {
    static func make(_ text: String,
                     size: CGFloat = 12,
                     weight: NSFont.Weight = .regular,
                     color: NSColor = .labelColor,
                     mono: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = mono ? Theme.mono(size, weight) : Theme.font(size, weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingMiddle
        field.translatesAutoresizingMaskIntoConstraints = false
        field.cell?.truncatesLastVisibleLine = true
        return field
    }
}
