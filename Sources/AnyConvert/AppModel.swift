import AppKit

@MainActor
protocol AppModelObserver: AnyObject {
    /// 列表结构或任务状态发生变化
    func modelJobsDidChange(_ model: AppModel)
    /// 单个任务的进度 / 状态更新（高频）
    func modelJobDidUpdate(_ model: AppModel, id: UUID)
    /// 转换设置变化
    func modelSettingsDidChange(_ model: AppModel)
    /// 队列全部结束
    func modelQueueDidFinish(_ model: AppModel)
    /// 需要提示给用户的信息
    func modelDidProduceMessage(_ model: AppModel, message: String)
}

@MainActor
final class AppModel {
    static let shared = AppModel()

    weak var observer: AppModelObserver?

    private(set) var jobs: [Job] = []
    private(set) var isRunning = false
    private(set) var ffmpegVersion = "检测中…"
    private(set) var lastOutputDirectory: URL?
    private(set) var hardwareAvailable = false

    private(set) var formatID = "mp4"
    private(set) var quality: Quality = .balanced
    private(set) var resolution: ResolutionPreset = .original
    private(set) var audioBitrate: AudioBitrate = .b192
    private(set) var hardware = false
    private(set) var outputMode: OutputMode = .alongside
    private(set) var customDirectory: URL?
    private(set) var customWidth: Int?
    private(set) var customHeight: Int?
    private(set) var extraArguments: [String] = []
    private(set) var targetSizeMB: Double?
    private(set) var allowDownscale = true
    private(set) var fps: Int = 0
    private(set) var maxConcurrent: Int = 3
    private(set) var docInstalling = false
    private(set) var docInstallProgress = 0.0
    private(set) var docInstallMessage = ""

    var docEngineReady: Bool { DocumentEngine.findSoffice() != nil }

    func installDocumentEngine() {
        guard !docInstalling else { return }
        docInstalling = true
        docInstallProgress = 0
        docInstallMessage = "准备下载…"
        observer?.modelSettingsDidChange(self)
        Task {
            do {
                try await EngineInstaller.install { [weak self] progress, message in
                    Task { @MainActor in
                        self?.docInstallProgress = progress
                        self?.docInstallMessage = message
                        self?.observer?.modelSettingsDidChange(self!)
                    }
                }
                await MainActor.run {
                    self.docInstalling = false
                    self.docInstallProgress = 1
                    self.docInstallMessage = "已就绪"
                    self.observer?.modelSettingsDidChange(self)
                    self.observer?.modelDidProduceMessage(self, message: "LibreOffice 安装完成")
                }
            } catch {
                await MainActor.run {
                    self.docInstalling = false
                    self.docInstallMessage = error.localizedDescription
                    self.observer?.modelSettingsDidChange(self)
                    self.observer?.modelDidProduceMessage(self, message: error.localizedDescription)
                }
            }
        }
    }

    private let engine = Engine.shared
    private let defaults = UserDefaults.standard
    private var runTask: Task<Void, Never>?

    private enum Keys {
        static let format = "ac.format"
        static let quality = "ac.quality"
        static let resolution = "ac.resolution"
        static let audioBitrate = "ac.audioBitrate"
        static let hardware = "ac.hardware"
        static let outputMode = "ac.outputMode"
        static let customDirectory = "ac.customDirectory"
        static let customWidth = "ac.customWidth"
        static let customHeight = "ac.customHeight"
        static let targetSizeMB = "ac.targetSizeMB"
        static let fps = "ac.fps"
        static let maxConcurrent = "ac.maxConcurrent"
        static let allowDownscale = "ac.allowDownscale"
    }

    private init() {}

    // MARK: - 启动

    func bootstrap() {
        loadSettings()
        acLog("bootstrap: version…")
        ffmpegVersion = Toolchain.versionString()
        acLog("bootstrap: version=\(ffmpegVersion)")
        hardwareAvailable = Toolchain.supportsVideoToolbox()
        acLog("bootstrap: hw=\(hardwareAvailable)")
        if !hardwareAvailable { hardware = false }
        if let dir = customDirectory, !FileManager.default.fileExists(atPath: dir.path) {
            customDirectory = nil
        }
    }

    private func loadSettings() {
        if let v = defaults.string(forKey: Keys.format), Catalog.all.contains(where: { $0.id == v }) { formatID = v }
        if let v = defaults.string(forKey: Keys.quality), let q = Quality(rawValue: v) { quality = q }
        if let v = defaults.string(forKey: Keys.resolution), let r = ResolutionPreset(rawValue: v) { resolution = r }
        if let v = defaults.string(forKey: Keys.audioBitrate), let b = AudioBitrate(rawValue: v) { audioBitrate = b }
        if defaults.object(forKey: Keys.hardware) != nil { hardware = defaults.bool(forKey: Keys.hardware) }
        if let v = defaults.string(forKey: Keys.outputMode), let m = OutputMode(rawValue: v) { outputMode = m }
        if let path = defaults.string(forKey: Keys.customDirectory), !path.isEmpty {
            customDirectory = URL(fileURLWithPath: path)
        }
        let storedWidth = defaults.integer(forKey: Keys.customWidth)
        let storedHeight = defaults.integer(forKey: Keys.customHeight)
        customWidth = storedWidth > 0 ? storedWidth : nil
        customHeight = storedHeight > 0 ? storedHeight : nil
        fps = defaults.integer(forKey: Keys.fps)
        let storedConcurrent = defaults.integer(forKey: Keys.maxConcurrent)
        maxConcurrent = storedConcurrent > 0 ? min(8, max(1, storedConcurrent)) : 3
        let storedTarget = defaults.double(forKey: Keys.targetSizeMB)
        targetSizeMB = storedTarget > 0 ? storedTarget : nil
        if defaults.object(forKey: Keys.allowDownscale) != nil {
            allowDownscale = defaults.bool(forKey: Keys.allowDownscale)
        }
    }

    // MARK: - 计算属性

    var currentFormat: OutputFormat { Catalog.format(formatID) }

    var canStart: Bool {
        !isRunning && jobs.contains { $0.status == .waiting || $0.status == .failed || $0.status == .cancelled }
    }

    var pendingCount: Int {
        jobs.filter { $0.status == .waiting || $0.status == .failed || $0.status == .cancelled }.count
    }

    var doneCount: Int { jobs.filter { $0.status == .done }.count }

    var summaryText: String {
        if isRunning {
            return L10n.t("footer.running", jobs.filter { $0.status == .running }.count, doneCount, jobs.count)
        }
        if jobs.isEmpty { return L10n.t("status.noFiles") }
        return L10n.t("footer.summary", jobs.count, doneCount)
    }

    // MARK: - 设置

    func setFormat(_ id: String) {
        guard formatID != id else { return }
        formatID = id
        defaults.set(id, forKey: Keys.format)
        for ext in pendingSourceExtensions() {
            defaults.set(id, forKey: "ac.target.\(ext)")
        }
        observer?.modelSettingsDidChange(self)
    }

    /// 当前待转换文件的源扩展名集合（用于「按源格式记住目标格式」）
    private func pendingSourceExtensions() -> Set<String> {
        var result: Set<String> = []
        for job in jobs where job.status == .waiting || job.status == .failed || job.status == .cancelled {
            let ext = job.url.pathExtension.lowercased()
            if !ext.isEmpty { result.insert(ext) }
        }
        return result
    }

    /// 恢复该源扩展名上次选择的目标格式（仅在列表原本为空时调用）
    /// 仅当所有待转换文件属于同一扩展名、且记住的目标仍可用时才恢复，避免混合批量误用
    private func restoreRememberedFormat(for extensionName: String) {
        let extensions = pendingSourceExtensions()
        guard extensions.count == 1, extensions.first == extensionName else { return }
        guard let remembered = defaults.string(forKey: "ac.target.\(extensionName)"),
              availableFormats.contains(where: { $0.id == remembered }),
              remembered != formatID else { return }
        formatID = remembered
        observer?.modelSettingsDidChange(self)
    }

    /// 当前文件集合可用的输出格式（能力筛选，参考飞鼠格式的 targets 接口）
    var availableFormats: [OutputFormat] {
        guard !jobs.isEmpty else { return Catalog.all }
        return Catalog.all.filter { format in
            jobs.allSatisfy { job in
                guard let info = job.info else { return true }
                switch format.kind {
                case .audio:
                    return info.hasAudio
                case .video:
                    return info.hasVideo && (!info.isImage || format.id == "gif")
                case .image:
                    return info.hasVideo
                case .document:
                    let ext = job.url.pathExtension.lowercased()
                    return DocumentEngine.isDocument(ext) || DocumentEngine.isImage(ext)
                }
            }
        }
    }

    /// 若当前目标格式与文件不兼容，自动切换到同类的可用格式
    func ensureValidFormat() {
        let allowed = Set(availableFormats.map(\.id))
        guard !allowed.contains(formatID) else { return }
        let kind = currentFormat.kind
        let fallback = availableFormats.first(where: { $0.kind == kind }) ?? availableFormats.first
        guard let choice = fallback else { return }
        formatID = choice.id
        defaults.set(choice.id, forKey: Keys.format)
        observer?.modelSettingsDidChange(self)
    }

    /// 应用预设（对应 File Converter 的 ConversionPreset 应用逻辑）
    func apply(preset: ConversionPreset) {
        formatID = preset.formatID
        quality = preset.quality
        resolution = preset.resolution
        audioBitrate = preset.bitrate
        hardware = preset.hardware && hardwareAvailable
        customWidth = preset.customWidth
        customHeight = preset.customHeight
        extraArguments = preset.extraArguments

        defaults.set(formatID, forKey: Keys.format)
        defaults.set(quality.rawValue, forKey: Keys.quality)
        defaults.set(resolution.rawValue, forKey: Keys.resolution)
        defaults.set(audioBitrate.rawValue, forKey: Keys.audioBitrate)
        defaults.set(hardware, forKey: Keys.hardware)
        defaults.set(customWidth ?? 0, forKey: Keys.customWidth)
        defaults.set(customHeight ?? 0, forKey: Keys.customHeight)
        for ext in pendingSourceExtensions() {
            defaults.set(formatID, forKey: "ac.target.\(ext)")
        }
        observer?.modelSettingsDidChange(self)
    }

    /// 当前设置快照（用于保存为预设）
    var currentSettingsSnapshot: ConversionSettings { makeSettings() }

    func tickElapsed() {
        guard isRunning else { return }
        var touched: [UUID] = []
        for index in jobs.indices where jobs[index].status == .running {
            if let started = jobs[index].startedAt {
                jobs[index].elapsed = Date().timeIntervalSince(started)
                touched.append(jobs[index].id)
            }
        }
        for id in touched { observer?.modelJobDidUpdate(self, id: id) }
    }

    func setQuality(_ value: Quality) {
        guard quality != value else { return }
        quality = value
        defaults.set(value.rawValue, forKey: Keys.quality)
        observer?.modelSettingsDidChange(self)
    }

    func setResolution(_ value: ResolutionPreset) {
        guard resolution != value else { return }
        resolution = value
        defaults.set(value.rawValue, forKey: Keys.resolution)
        observer?.modelSettingsDidChange(self)
    }

    func setAudioBitrate(_ value: AudioBitrate) {
        guard audioBitrate != value else { return }
        audioBitrate = value
        defaults.set(value.rawValue, forKey: Keys.audioBitrate)
        observer?.modelSettingsDidChange(self)
    }

    func setHardware(_ value: Bool) {
        guard hardware != value else { return }
        hardware = value
        defaults.set(value, forKey: Keys.hardware)
        observer?.modelSettingsDidChange(self)
    }

    func setOutputMode(_ value: OutputMode) {
        guard outputMode != value else { return }
        outputMode = value
        defaults.set(value.rawValue, forKey: Keys.outputMode)
        observer?.modelSettingsDidChange(self)
    }

    func setTargetSizeMB(_ value: Double?) {
        let normalized: Double? = (value ?? 0) > 0 ? value : nil
        guard targetSizeMB != normalized else { return }
        targetSizeMB = normalized
        defaults.set(normalized ?? 0, forKey: Keys.targetSizeMB)
        observer?.modelSettingsDidChange(self)
    }

    func setFPS(_ value: Int) {
        guard fps != value else { return }
        fps = max(0, value)
        defaults.set(fps, forKey: Keys.fps)
        observer?.modelSettingsDidChange(self)
    }

    func setMaxConcurrent(_ value: Int) {
        let clamped = min(8, max(1, value))
        guard maxConcurrent != clamped else { return }
        maxConcurrent = clamped
        defaults.set(clamped, forKey: Keys.maxConcurrent)
        observer?.modelSettingsDidChange(self)
    }

    func setAllowDownscale(_ value: Bool) {
        guard allowDownscale != value else { return }
        allowDownscale = value
        defaults.set(value, forKey: Keys.allowDownscale)
        observer?.modelSettingsDidChange(self)
    }

    func setCustomResolution(width: Int?, height: Int?) {
        guard customWidth != width || customHeight != height else { return }
        customWidth = width
        customHeight = height
        defaults.set(width ?? 0, forKey: Keys.customWidth)
        defaults.set(height ?? 0, forKey: Keys.customHeight)
        observer?.modelSettingsDidChange(self)
    }

    func setCustomDirectory(_ url: URL?) {
        customDirectory = url
        defaults.set(url?.path, forKey: Keys.customDirectory)
        observer?.modelSettingsDidChange(self)
    }

    // MARK: - 文件管理

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.title = "选择要转换的文件"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择包含音视频的文件夹"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    func pickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择输出文件夹"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = customDirectory
        if panel.runModal() == .OK, let url = panel.url {
            setCustomDirectory(url)
        }
    }

    func addFiles(_ urls: [URL]) {
        let expanded = FileUtilities.expand(urls: urls)
        guard !expanded.isEmpty else {
            observer?.modelDidProduceMessage(self, message: L10n.t("msg.noMedia"))
            return
        }

        let wasEmpty = jobs.isEmpty
        let existing = Set(jobs.map { $0.url.standardizedFileURL })
        var added: [UUID] = []
        for url in expanded {
            let standardized = url.standardizedFileURL
            if existing.contains(standardized) { continue }
            if jobs.contains(where: { $0.url.standardizedFileURL == standardized }) { continue }
            let sourceExt = standardized.pathExtension.lowercased()
            if DocumentEngine.isDocument(sourceExt) {
                // 拖入文档时自动切到 PDF，避免用户在媒体格式下看到“不支持”
                if !DocumentEngine.canConvert(target: currentFormat.ext, sourceExt: sourceExt) {
                    setFormat("pdf")
                }
                guard DocumentEngine.canConvert(target: currentFormat.ext, sourceExt: sourceExt) else {
                    observer?.modelDidProduceMessage(self, message: L10n.t("msg.docUnsupported", sourceExt, currentFormat.ext))
                    continue
                }
            } else if currentFormat.kind == .document {
                guard DocumentEngine.canConvert(target: currentFormat.ext, sourceExt: sourceExt) else {
                    observer?.modelDidProduceMessage(self, message: L10n.t("msg.docUnsupported", sourceExt, currentFormat.ext))
                    continue
                }
            }
            let job = Job(url: standardized, status: .probing)
            jobs.append(job)
            added.append(job.id)
        }

        guard !added.isEmpty else {
            observer?.modelDidProduceMessage(self, message: L10n.t("msg.duplicate"))
            return
        }
        observer?.modelJobsDidChange(self)
        if wasEmpty, let first = added.first, let job = job(for: first) {
            restoreRememberedFormat(for: job.url.pathExtension.lowercased())
        }
        probe(added)
    }

    private func probe(_ ids: [UUID]) {
        let pairs: [(UUID, URL)] = ids.compactMap { id in
            jobs.first(where: { $0.id == id }).map { (id, $0.url) }
        }
        Task.detached(priority: .userInitiated) {
            for (id, url) in pairs {
                if DocumentEngine.isDocument(url.pathExtension.lowercased()) {
                    await MainActor.run { self.markDocumentReady(id) }
                    continue
                }
                do {
                    let info = try await MediaProbe.probe(url)
                    await MainActor.run { self.apply(info: info, to: id) }
                } catch {
                    await MainActor.run { self.applyProbeFailure(error.localizedDescription, to: id) }
                }
            }
        }
    }

    private func apply(info: MediaInfo, to id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].info = info
        if jobs[index].status == .probing { jobs[index].status = .waiting }
        observer?.modelJobsDidChange(self)
    }

    private func applyProbeFailure(_ message: String, to id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = .failed
        jobs[index].message = message
        observer?.modelJobsDidChange(self)
    }

    func remove(_ id: UUID) {
        guard !isRunning else {
            observer?.modelDidProduceMessage(self, message: L10n.t("msg.cancelFirst"))
            return
        }
        jobs.removeAll { $0.id == id }
        observer?.modelJobsDidChange(self)
    }

    func job(for id: UUID) -> Job? {
        jobs.first { $0.id == id }
    }

    func retry(_ id: UUID) {
        guard !isRunning, let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = .waiting
        jobs[index].message = ""
        jobs[index].progress = 0
        observer?.modelJobDidUpdate(self, id: id)
        start()
    }

    func clearAll() {
        guard !isRunning else {
            observer?.modelDidProduceMessage(self, message: L10n.t("msg.cancelFirst"))
            return
        }
        jobs.removeAll()
        lastOutputDirectory = nil
        observer?.modelJobsDidChange(self)
    }

    func clearFinished() {
        guard !isRunning else { return }
        jobs.removeAll { $0.status == .done }
        observer?.modelJobsDidChange(self)
    }

    func reveal(_ id: UUID) {
        guard let job = job(for: id) else { return }
        if let out = job.outputURL, FileManager.default.fileExists(atPath: out.path) {
            FileUtilities.reveal(out)
        } else {
            FileUtilities.reveal(job.url)
        }
    }

    func openOutputFolder() {
        let dir = lastOutputDirectory ?? jobs.last?.url.deletingLastPathComponent()
        if let dir, FileManager.default.fileExists(atPath: dir.path) {
            NSWorkspace.shared.open(dir)
        }
    }

    // MARK: - 转换流程

    func start() {
        guard !isRunning else { return }

        let ids = jobs.filter {
            $0.status == .waiting || $0.status == .failed || $0.status == .cancelled
        }.map(\.id)

        guard !ids.isEmpty else {
            observer?.modelDidProduceMessage(self, message: L10n.t("msg.noPending"))
            return
        }

        if outputMode == .custom {
            guard let dir = customDirectory else {
                observer?.modelDidProduceMessage(self, message: L10n.t("msg.chooseOutput"))
                return
            }
            if !FileManager.default.fileExists(atPath: dir.path) {
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                } catch {
                    observer?.modelDidProduceMessage(self, message: L10n.t("msg.createDirFail", error.localizedDescription))
                    return
                }
            }
        }

        isRunning = true
        engine.resetCancellation()
        let settings = makeSettings()
        let limit = maxConcurrent
        observer?.modelJobsDidChange(self)

        runTask = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                var iterator = ids.makeIterator()
                var running = 0
                while running < limit, let id = iterator.next() {
                    group.addTask { await self.convert(id: id, settings: settings) }
                    running += 1
                }
                for await _ in group {
                    if Task.isCancelled { break }
                    guard let id = iterator.next() else { continue }
                    group.addTask { await self.convert(id: id, settings: settings) }
                }
            }
            self.isRunning = false
            self.observer?.modelQueueDidFinish(self)
            self.observer?.modelJobsDidChange(self)
        }
    }

    func cancel() {
        runTask?.cancel()
        engine.cancel()
    }

    private func makeSettings() -> ConversionSettings {
        ConversionSettings(
            format: currentFormat,
            quality: quality,
            resolution: resolution,
            audioBitrate: audioBitrate,
            hardware: hardware && hardwareAvailable && currentFormat.kind == .video && !currentFormat.isAnimatedImage,
            customWidth: customWidth,
            customHeight: customHeight,
            extraArguments: extraArguments,
            targetBytes: (currentFormat.kind == .image || currentFormat.kind == .video)
                ? targetSizeMB.map { Int64($0 * 1024 * 1024) } : nil,
            allowDownscale: allowDownscale,
            fps: fps
        )
    }

    private func outputDirectory(for input: URL) -> URL {
        if outputMode == .custom, let dir = customDirectory { return dir }
        return input.deletingLastPathComponent()
    }

    private func markDocumentReady(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].info = MediaInfo()
        jobs[index].status = .waiting
        jobs[index].message = L10n.t("group.document")
        observer?.modelJobDidUpdate(self, id: id)
    }

    private func convertDocument(id: UUID, job: Job, settings: ConversionSettings) async {
        let sourceExt = job.url.pathExtension.lowercased()
        guard DocumentEngine.canConvert(target: settings.format.ext, sourceExt: sourceExt) else {
            fail(id, message: L10n.t("msg.docUnsupported", sourceExt, settings.format.ext))
            return
        }
        let directory = outputDirectory(for: job.url)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let output = FileUtilities.outputURL(for: job.url, ext: settings.format.ext, directory: directory)

        guard let runningIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[runningIndex].status = .running
        jobs[runningIndex].progress = 0
        jobs[runningIndex].message = L10n.t("group.document")
        jobs[runningIndex].startedAt = Date()
        observer?.modelJobDidUpdate(self, id: id)

        do {
            try await DocumentEngine.convert(src: job.url, target: settings.format, output: output) { [weak self] percent in
                Task { @MainActor in self?.updateProgress(jobID: id, percent: percent, speed: "") }
            }
            guard let doneIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
            jobs[doneIndex].status = .done
            jobs[doneIndex].progress = 1
            jobs[doneIndex].outputURL = output
            jobs[doneIndex].message = ""
            jobs[doneIndex].elapsed = jobs[doneIndex].startedAt.map { Date().timeIntervalSince($0) } ?? 0
            jobs[doneIndex].startedAt = nil
            lastOutputDirectory = directory
            observer?.modelJobDidUpdate(self, id: id)
        } catch {
            try? FileManager.default.removeItem(at: output)
            fail(id, message: error.localizedDescription)
        }
    }

    private func convert(id: UUID, settings: ConversionSettings) async {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let job = jobs[index]
        if settings.format.kind == .document
            || DocumentEngine.isDocument(job.url.pathExtension.lowercased()) {
            await convertDocument(id: id, job: job, settings: settings)
            return
        }

        var media = job.info
        if media == nil {
            do {
                media = try await MediaProbe.probe(job.url)
                if let media { apply(info: media, to: id) }
            } catch {
                fail(id, message: error.localizedDescription)
                return
            }
        }
        guard let info = media else { return }

        if settings.format.kind == .audio, !info.hasAudio {
            fail(id, message: ConvertError.noAudioTrack.localizedDescription)
            return
        }
        if settings.format.kind == .video, !info.hasVideo {
            fail(id, message: ConvertError.noVideoTrack.localizedDescription)
            return
        }
        if settings.format.kind == .image, !info.hasVideo {
            fail(id, message: ConvertError.noVideoTrack.localizedDescription)
            return
        }
        if settings.format.kind == .video, info.isImage, settings.format.id != "gif" {
            fail(id, message: ConvertError.imageNeedsImageFormat.localizedDescription)
            return
        }
        if info.width > 0, info.height > 0, info.width * info.height > 100_000_000 {
            fail(id, message: L10n.t("msg.tooLarge"))
            return
        }

        let directory = outputDirectory(for: job.url)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let output = FileUtilities.outputURL(for: job.url, ext: settings.format.ext, directory: directory)

        guard let runningIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[runningIndex].status = .running
        jobs[runningIndex].progress = 0
        jobs[runningIndex].speed = ""
        jobs[runningIndex].message = ""
        jobs[runningIndex].startedAt = Date()
        jobs[runningIndex].elapsed = 0
        observer?.modelJobDidUpdate(self, id: id)

        do {
            try await runConversion(settings: settings, job: job, info: info, output: output)
            guard let doneIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
            jobs[doneIndex].status = .done
            jobs[doneIndex].progress = 1
            jobs[doneIndex].speed = ""
            jobs[doneIndex].outputURL = output
            jobs[doneIndex].elapsed = jobs[doneIndex].startedAt.map { Date().timeIntervalSince($0) } ?? jobs[doneIndex].elapsed
            jobs[doneIndex].startedAt = nil
            lastOutputDirectory = directory
            observer?.modelJobDidUpdate(self, id: id)
        } catch let error as ConvertError {
            try? FileManager.default.removeItem(at: output)
            if case .cancelled = error {
                markCancelled(id)
            } else {
                fail(id, message: error.localizedDescription)
            }
        } catch {
            try? FileManager.default.removeItem(at: output)
            fail(id, message: error.localizedDescription)
        }
    }

    private func runConversion(settings: ConversionSettings,
                               job: Job,
                               info: MediaInfo,
                               output: URL) async throws {
        if let targetBytes = settings.targetBytes, targetBytes > 0 {
            try await CompressionEngine.compress(input: job.url, settings: settings,
                                                 output: output, info: info) { [weak self] percent, speed in
                Task { @MainActor in self?.updateProgress(jobID: job.id, percent: percent, speed: speed) }
            }
            return
        }

        guard let conversionEngine = EngineRegistry.engine(for: settings.format),
              var arguments = conversionEngine.arguments(for: settings, input: job.url, output: output, info: info) else {
            throw ConvertError.encodeFailed("No engine available")
        }

        do {
            try await engine.run(arguments: arguments, duration: info.duration) { [weak self] percent, speed in
                Task { @MainActor in self?.updateProgress(jobID: job.id, percent: percent, speed: speed) }
            }
        } catch let error as ConvertError {
            guard case .encodeFailed = error, settings.hardware else { throw error }
            // 硬件编码不可用 → 自动回退到软件编码
            var software = settings
            software.hardware = false
            arguments = EngineRegistry.engine(for: software.format)?.arguments(
                for: software, input: job.url, output: output, info: info) ?? arguments
            try? FileManager.default.removeItem(at: output)
            try await engine.run(arguments: arguments, duration: info.duration) { [weak self] percent, speed in
                Task { @MainActor in self?.updateProgress(jobID: job.id, percent: percent, speed: speed) }
            }
            if let index = jobs.firstIndex(where: { $0.id == job.id }) {
                jobs[index].message = L10n.t("msg.hwFallback")
                observer?.modelJobDidUpdate(self, id: job.id)
            }
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)??.int64Value ?? 0
        guard size > 0 else {
            throw ConvertError.encodeFailed("输出文件为空，转换未成功。")
        }
    }

    private func updateProgress(jobID: UUID, percent: Double, speed: String) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].progress = percent
        jobs[index].speed = speed
        if let started = jobs[index].startedAt {
            jobs[index].elapsed = Date().timeIntervalSince(started)
        }
        observer?.modelJobDidUpdate(self, id: jobID)
    }

    private func markCancelled(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = .cancelled
        jobs[index].progress = 0
        jobs[index].speed = ""
        jobs[index].elapsed = jobs[index].startedAt.map { Date().timeIntervalSince($0) } ?? jobs[index].elapsed
        jobs[index].startedAt = nil
        observer?.modelJobDidUpdate(self, id: id)
    }

    private func fail(_ id: UUID, message: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].status = .failed
        jobs[index].speed = ""
        jobs[index].message = message
        jobs[index].elapsed = jobs[index].startedAt.map { Date().timeIntervalSince($0) } ?? jobs[index].elapsed
        jobs[index].startedAt = nil
        observer?.modelJobDidUpdate(self, id: id)
    }
}
